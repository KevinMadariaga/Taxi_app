import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/services/map_service.dart' as core_map;

import '../services/firebase_service.dart';
import '../services/local_cache_service.dart';
import '../services/trip_route_math_service.dart';

enum TipoUsuarioTracking { cliente, conductor }

enum RouteTrackingFocusMode { destino, ambos }

class TripRouteTrackingViewModel extends ChangeNotifier {
  TripRouteTrackingViewModel({
    required this.solicitudId,
    required this.currentUserId,
    required this.tipoUsuario,
    FirebaseService? firebaseService,
    LocalCacheService? localCacheService,
    TripRouteMathService? mathService,
    core_map.MapService? googleRouteService,
  }) : _firebaseService = firebaseService ?? FirebaseService(),
       _localCacheService = localCacheService ?? LocalCacheService(),
       _mathService = mathService ?? const TripRouteMathService(),
       _googleRouteService = googleRouteService ?? const core_map.MapService();

  final String solicitudId;
  final String currentUserId;
  final TipoUsuarioTracking tipoUsuario;

  final FirebaseService _firebaseService;
  final LocalCacheService _localCacheService;
  final TripRouteMathService _mathService;
  final core_map.MapService _googleRouteService;

  StreamSubscription<Map<String, dynamic>>? _solicitudSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Position>? _driverLocationSub;

  bool _disposed = false;
  bool _completionHandled = false;
  bool _routeBootstrapped = false;

  DateTime? _lastDriverWriteAt;
  LatLng? _lastDriverSentPoint;
  DateTime? _lastRouteRecalculatedAt;

  int _offRouteCounter = 0;

  String estadoSolicitud = '';
  bool isLoading = true;
  bool isOffline = false;
  bool isSyncingPendingLocations = false;
  bool isUpdatingRoute = false;
  bool isCompletingTrip = false;
  bool shouldNavigateToSummary = false;

  RouteTrackingFocusMode focusMode = RouteTrackingFocusMode.ambos;

  LatLng? conductorLatLng;
  LatLng? destinoLatLng;
  List<LatLng> routePoints = const [];

  double? distanceRemainingMeters;
  Duration? etaRemaining;

  String userDisplayName = '';
  String userPhotoUrl = '';
  String destinationLabel = '';
  String vehiclePlate = '';
  String vehiclePhotoUrl = '';

  Future<void> init() async {
    await _restoreRouteCache();
    await _bindConnectivity();
    _bindSolicitud();

    if (isConductor) {
      await _startDriverLocationTracking();
    }
  }

  bool get isConductor => tipoUsuario == TipoUsuarioTracking.conductor;

  String get distanceText {
    final value = distanceRemainingMeters;
    if (value == null) return '--';
    return _mathService.formatDistance(value);
  }

  String get etaText {
    final value = etaRemaining;
    if (value == null) return '--';
    return _mathService.formatEta(value);
  }

  String get offlineText => 'Sin conexión, reconectando...';

  String? get shareLocationUrl {
    final point = conductorLatLng;
    if (point == null) return null;
    return 'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
  }

  String get destinationText {
    if (destinationLabel.trim().isNotEmpty) return destinationLabel.trim();
    final point = destinoLatLng;
    if (point == null) return 'Destino no disponible';
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<void> toggleFocusMode() async {
    focusMode = focusMode == RouteTrackingFocusMode.destino
        ? RouteTrackingFocusMode.ambos
        : RouteTrackingFocusMode.destino;
    _safeNotify();
  }

  void consumeSummaryNavigation() {
    shouldNavigateToSummary = false;
    _safeNotify();
  }

  Future<void> finalizarViajePorConductor() async {
    if (!isConductor || isCompletingTrip) return;

    isCompletingTrip = true;
    _safeNotify();

    try {
      await _firebaseService.actualizarEstadoSolicitud(
        solicitudId: solicitudId,
        estado: 'completado',
      );

      _completionHandled = true;
      shouldNavigateToSummary = true;
    } catch (_) {
      isCompletingTrip = false;
      rethrow;
    }

    _safeNotify();
  }

  void _bindSolicitud() {
    _solicitudSub?.cancel();
    _solicitudSub = _firebaseService.watchSolicitudRaw(solicitudId).listen(
      (raw) async {
        isLoading = false;
        await _hydrateFromSolicitud(raw);
        _handleStateTransitions();

        if (!_routeBootstrapped && routePoints.length >= 2) {
          _routeBootstrapped = true;
        }

        final routeExistsInFirestore = _extractRoutePoints(raw).length >= 2;
        if (!routeExistsInFirestore && !_routeBootstrapped) {
          await _ensurePersistedRoute(forceRecalculate: false);
        }

        if (routePoints.length >= 2) {
          await _maybeRecalculateByDeviation();
        }

        if (!isOffline && isConductor) {
          await _flushPendingDriverLocations();
        }

        _safeNotify();
      },
      onError: (error) {
        isLoading = false;
        _safeNotify();
      },
    );
  }

  Future<void> _bindConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    isOffline = _isOfflineFromConnectivity(result);

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final nextOffline = _isOfflineFromConnectivity(result);
      if (nextOffline == isOffline) return;

      isOffline = nextOffline;
      _safeNotify();

      if (!isOffline) {
        _flushPendingDriverLocations();
        _ensurePersistedRoute(forceRecalculate: false);
      }
    });
  }

  bool _isOfflineFromConnectivity(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((entry) => entry == ConnectivityResult.none);
  }

  Future<void> _startDriverLocationTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _driverLocationSub?.cancel();
      _driverLocationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1, //distancia metros
        ),
      ).listen((position) {
        final point = LatLng(position.latitude, position.longitude);
        _onDriverPositionFromDevice(point);
      });
    } catch (_) {
      // Keep UI responsive even if location permission fails.
    }
  }

  Future<void> _onDriverPositionFromDevice(LatLng point) async {
    conductorLatLng = point;
    _updateRemainingMetrics();
    _safeNotify();

    final now = DateTime.now();
    if (_lastDriverWriteAt != null &&
        now.difference(_lastDriverWriteAt!) < const Duration(seconds: 4)) {
      return;
    }

    if (_lastDriverSentPoint != null) {
      final moved = _mathService.haversineMeters(_lastDriverSentPoint!, point);
      if (moved < 8) {
        return;
      }
    }

    _lastDriverWriteAt = now;

    if (isOffline) {
      await _localCacheService.appendPendingConductorLocation(
        solicitudId: solicitudId,
        lat: point.latitude,
        lng: point.longitude,
        timestampMs: now.millisecondsSinceEpoch,
      );
      return;
    }

    try {
      await _firebaseService.actualizarUbicacionConductorEnSolicitud(
        solicitudId: solicitudId,
        location: point,
        timestampMs: now.millisecondsSinceEpoch,
        appendRouteHistory: true,
      );
      _lastDriverSentPoint = point;
    } catch (_) {
      await _localCacheService.appendPendingConductorLocation(
        solicitudId: solicitudId,
        lat: point.latitude,
        lng: point.longitude,
        timestampMs: now.millisecondsSinceEpoch,
      );
    }

    await _maybeRecalculateByDeviation();
  }

  Future<void> _flushPendingDriverLocations() async {
    if (!isConductor || isSyncingPendingLocations || isOffline) return;

    final pending = await _localCacheService.readPendingConductorLocations(
      solicitudId,
    );
    if (pending.isEmpty) return;

    isSyncingPendingLocations = true;
    _safeNotify();

    final failed = <PendingConductorLocation>[];

    for (final item in pending) {
      try {
        final point = LatLng(item.lat, item.lng);
        await _firebaseService.actualizarUbicacionConductorEnSolicitud(
          solicitudId: solicitudId,
          location: point,
          timestampMs: item.timestampMs,
          appendRouteHistory: true,
        );
        _lastDriverSentPoint = point;
      } catch (_) {
        failed.add(item);
      }
    }

    if (failed.isEmpty) {
      await _localCacheService.clearPendingConductorLocations(solicitudId);
    } else {
      await _localCacheService.clearPendingConductorLocations(solicitudId);
      for (final item in failed) {
        await _localCacheService.appendPendingConductorLocation(
          solicitudId: solicitudId,
          lat: item.lat,
          lng: item.lng,
          timestampMs: item.timestampMs,
        );
      }
    }

    isSyncingPendingLocations = false;
    _safeNotify();
  }

  Future<void> _restoreRouteCache() async {
    final cachedRoute = await _localCacheService.readRoute(solicitudId);
    if (cachedRoute != null && cachedRoute.points.length >= 2) {
      routePoints = cachedRoute.points;
      distanceRemainingMeters = cachedRoute.distanceMeters;
      if (cachedRoute.etaSeconds != null) {
        etaRemaining = Duration(seconds: cachedRoute.etaSeconds!);
      }
      _routeBootstrapped = true;
    }
  }

  Future<void> _hydrateFromSolicitud(Map<String, dynamic> data) async {
    estadoSolicitud = ((data['estado'] ?? data['status']) ?? '')
        .toString()
        .toLowerCase()
        .trim();

    final conductorMap = _asStringMap(data['conductor']);
    final clienteMap = _asStringMap(data['cliente']);
    final destinoMap = _asStringMap(data['destino']);

    conductorLatLng = _extractPoint(conductorMap);
    destinoLatLng = _extractPoint(destinoMap);

    final firestoreRoute = _extractRoutePoints(data);
    if (firestoreRoute.length >= 2) {
      routePoints = firestoreRoute;
      _routeBootstrapped = true;
      await _localCacheService.saveRoute(
        solicitudId: solicitudId,
        points: routePoints,
        distanceMeters: _mathService.polylineDistanceMeters(routePoints),
        etaSeconds: _mathService
            .etaFromDistance(_mathService.polylineDistanceMeters(routePoints))
            .inSeconds,
      );
    }

    if (tipoUsuario == TipoUsuarioTracking.conductor) {
      userDisplayName = _readName(clienteMap, fallback: 'Cliente');
      userPhotoUrl = _readPhoto(clienteMap);
    } else {
      userDisplayName = _readName(conductorMap, fallback: 'Conductor');
      userPhotoUrl = _readPhoto(conductorMap);
    }

    destinationLabel = _readDestinationLabel(destinoMap);

    vehiclePlate = _readVehiclePlate(conductorMap);
    vehiclePhotoUrl = _readVehiclePhoto(conductorMap);

    _updateRemainingMetrics();
  }

  List<LatLng> _extractRoutePoints(Map<String, dynamic> data) {
    final tracking = _asStringMap(data['tracking']);
    final route = _asStringMap(tracking?['route']);
    final rawPoints = route?['points'];

    if (rawPoints is! List) return const [];

    return rawPoints
        .map((item) => _asStringMap(item))
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final lat = (item['lat'] as num?)?.toDouble();
          final lng = (item['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList(growable: false);
  }

  Future<void> _ensurePersistedRoute({required bool forceRecalculate}) async {
    if (isOffline || isUpdatingRoute) return;

    final from = conductorLatLng;
    final to = destinoLatLng;
    if (from == null || to == null) return;

    if (!forceRecalculate && routePoints.length >= 2) return;

    isUpdatingRoute = true;
    _safeNotify();

    try {
      final generated = await _googleRouteService.getRoutePolyline(from, to);
      if (generated.length < 2) return;

      routePoints = generated;
      _routeBootstrapped = true;

      final distance = _mathService.polylineDistanceMeters(routePoints);
      distanceRemainingMeters = distance;
      etaRemaining = _mathService.etaFromDistance(distance);

      await _firebaseService.guardarRutaPersistida(
        solicitudId: solicitudId,
        points: routePoints,
        distanceMeters: distance,
        source: 'google_directions',
        recalculatedByDeviation: forceRecalculate,
      );

      await _localCacheService.saveRoute(
        solicitudId: solicitudId,
        points: routePoints,
        distanceMeters: distance,
        etaSeconds: etaRemaining?.inSeconds,
      );

      if (forceRecalculate) {
        _lastRouteRecalculatedAt = DateTime.now();
      }
    } catch (_) {
      // Keep last known route if route refresh fails.
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  Future<void> _maybeRecalculateByDeviation() async {
    final current = conductorLatLng;
    if (current == null || routePoints.length < 2 || isOffline) return;

    final distanceToRoute = _mathService.minDistanceToPolylineMeters(
      current,
      routePoints,
    );

    if (distanceToRoute <= 50) {
      _offRouteCounter = 0;
      return;
    }

    _offRouteCounter += 1;
    if (_offRouteCounter < 2) return;

    final now = DateTime.now();
    if (_lastRouteRecalculatedAt != null &&
        now.difference(_lastRouteRecalculatedAt!) <
            const Duration(seconds: 45)) {
      return;
    }

    _offRouteCounter = 0;
    await _ensurePersistedRoute(forceRecalculate: true);
  }

  void _updateRemainingMetrics() {
    final current = conductorLatLng;
    if (current == null || routePoints.length < 2) {
      distanceRemainingMeters = null;
      etaRemaining = null;
      return;
    }

    final remaining = _mathService.remainingDistanceMeters(current, routePoints);
    distanceRemainingMeters = remaining;
    etaRemaining = _mathService.etaFromDistance(remaining);
  }

  void _handleStateTransitions() {
    if (_completionHandled) return;

    final normalized = _normalizeEstado(estadoSolicitud);
    if (normalized != 'completado') return;

    _completionHandled = true;
    isCompletingTrip = true;
    shouldNavigateToSummary = true;
  }

  String _normalizeEstado(String rawEstado) {
    final raw = rawEstado.toLowerCase().trim();
    final compact = raw.replaceAll('_', ' ').replaceAll('-', ' ');
    if (compact.contains('completad')) return 'completado';
    if (compact.contains('completed')) return 'completado';
    if (compact.contains('finaliz')) return 'completado';
    return compact;
  }

  LatLng? _extractPoint(Map<String, dynamic>? data) {
    if (data == null) return null;

    final nested = _asStringMap(data['ubicacion']);
    final lat = (nested?['lat'] ?? data['lat'] ?? data['latitude']) as num?;
    final lng =
        (nested?['lng'] ?? data['lng'] ?? data['longitude'] ?? data['longitud'])
            as num?;

    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  String _readName(Map<String, dynamic>? data, {required String fallback}) {
    final value =
        (data?['nombre'] ?? data?['name'] ?? data?['displayName'] ?? '')
            .toString()
            .trim();
    return value.isEmpty ? fallback : value;
  }

  String _readPhoto(Map<String, dynamic>? data) {
    final photo =
        (data?['foto'] ??
                data?['photo'] ??
                data?['photoUrl'] ??
                data?['imagen'] ??
                data?['avatar'] ??
                '')
            .toString()
            .trim();
    return photo;
  }

  String _readVehiclePlate(Map<String, dynamic>? data) {
    return (data?['placa'] ??
            data?['placaVehiculo'] ??
            data?['vehiclePlate'] ??
            data?['placa_auto'] ??
            '')
        .toString()
        .trim();
  }

  String _readVehiclePhoto(Map<String, dynamic>? data) {
    return (data?['fotoVehiculo'] ??
            data?['vehiclePhoto'] ??
            data?['foto_carro'] ??
            data?['fotoAuto'] ??
            '')
        .toString()
        .trim();
  }

  String _readDestinationLabel(Map<String, dynamic>? data) {
    if (data == null) return '';
    final label = (data['direccion'] ?? data['title'] ?? data['address'] ?? '')
        .toString()
        .trim();
    return label;
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is! Map) return null;
    final out = <String, dynamic>{};
    value.forEach((key, entry) {
      out[key.toString()] = entry;
    });
    return out;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _solicitudSub?.cancel();
    _connectivitySub?.cancel();
    _driverLocationSub?.cancel();
    super.dispose();
  }
}
