import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/services/route_cache_service.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

import '../services/firebase_service.dart';
import '../services/local_cache_service.dart';
import '../services/map_service.dart' as tracking_map;
import '../services/trip_route_math_service.dart';

enum TipoUsuarioTracking { cliente, conductor }

enum RouteTrackingFocusMode { destino, ambos }

class TripRouteTrackingViewModel extends ChangeNotifier {
  TripRouteTrackingViewModel({
    required this.solicitudId,
    required this.currentUserId,
    required this.tipoUsuario,
    TripTrackingFirebaseService? firebaseService,
    LocalCacheService? localCacheService,
    TripRouteMathService? mathService,
    tracking_map.MapService? routeService,
  }) : _firebaseService = firebaseService ?? TripTrackingFirebaseService(),
       _localCacheService = localCacheService ?? LocalCacheService(),
       _mathService = mathService ?? const TripRouteMathService(),
       _routeService = routeService ?? tracking_map.MapService();

  final String solicitudId;
  final String currentUserId;
  final TipoUsuarioTracking tipoUsuario;

  final TripTrackingFirebaseService _firebaseService;
  final LocalCacheService _localCacheService;
  final TripRouteMathService _mathService;
  final tracking_map.MapService _routeService;
  int? _lastNearestIndex;

  StreamSubscription<Map<String, dynamic>>? _solicitudSub;
  StreamSubscription<dynamic>? _connectivitySub;
  StreamSubscription<Position>? _driverLocationSub;
  TrackingService? _foregroundTrackingService;

  bool _disposed = false;
  bool _completionHandled = false;
  bool _routeBootstrapped = false;

  DateTime? _lastDriverWriteAt;
  LatLng? _lastDriverSentPoint;
  DateTime? _lastRouteRecalcAt;

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
  double conductorHeading = 0.0;

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
    } else {
      // Cliente: no escuchar la ubicación del conductor desde Firestore para
      // mover el marcador localmente. Iniciamos tracking en el dispositivo
      // cliente y actualizamos el marcador de coche con la posición local.
      await _startClientLocationTracking();
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

  // Route is generated once and then visually consumed as the conductor advances.
  List<LatLng> get visibleRoutePoints {
    final points = routePoints;
    final current = conductorLatLng;
    if (points.length < 2 || current == null) {
      return points;
    }
    final nearest = _mathService.nearestPointIndex(current, points);
    final start = nearest.clamp(0, points.length - 1);
    final tail = points.sublist(start);
    if (tail.isEmpty) return points;

    try {
      if (_lastNearestIndex == null || _lastNearestIndex != nearest) {
        debugPrint('[TripRouteTrackingViewModel] nearest route index: $nearest, tail length: ${tail.length}');
        _lastNearestIndex = nearest;
      }
    } catch (_) {}

    return [current, ...tail];
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
    // Optimistic flow: navigate immediately, perform network/cleanup in background
    isCompletingTrip = false;
    _completionHandled = true;
    shouldNavigateToSummary = true;
    _safeNotify();

    unawaited(Future<void>(() async {
      try {
        await _firebaseService.actualizarEstadoSolicitud(
          solicitudId: solicitudId,
          estado: SolicitudEstado.completado,
        );
      } catch (e) {
        // Log or handle failure to update remote state; do not block navigation
        if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] Error updating estado remotely: $e');
      }

      try {
        _foregroundTrackingService?.dispose();
      } catch (_) {}

      try {
        final service = FlutterBackgroundService();
        service.invoke('stop');
      } catch (_) {}

      try {
        await NotificacionesServicio.instance.cancelAll();
      } catch (_) {}

      try {
        await SessionHelper.clearActiveSolicitud();
      } catch (_) {}

      try {
        await RouteCacheService.clearSolicitud(solicitudId);
      } catch (_) {}
      }));
  }

  void _bindSolicitud() {
    _solicitudSub?.cancel();

    if (isConductor) {
      // Conductor: escuchar cambios en la solicitud en tiempo real.
      _solicitudSub = _firebaseService
          .watchSolicitudRaw(solicitudId)
          .listen(
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
    } else {
      // Cliente: escuchar en tiempo real la solicitud para recibir la
      // ubicación del conductor y mover el marcador mientras se actualiza.
      _solicitudSub = _firebaseService
          .watchSolicitudRaw(solicitudId)
          .listen((raw) async {
        try {
          isLoading = false;
          // Hidratamos campos comunes (destino, ruta, user info, etc.)
          await _hydrateFromSolicitud(raw);

          if (!_routeBootstrapped && routePoints.length >= 2) {
            _routeBootstrapped = true;
          }

          // Verificar transiciones de estado (p.ej. completar viaje)
          _handleStateTransitions();

          // Extraer explícitamente la ubicación del conductor desde el
          // documento y asignarla en cliente (hydrate solo asigna para
          // el conductor local).
          final conductorMap = _asStringMap(raw['conductor']);
          final remoteConductor = _extractPoint(conductorMap);
          if (remoteConductor != null) {
            conductorLatLng = remoteConductor;
          }

          _updateRemainingMetrics();
        } catch (_) {
          // Ignorar errores de parseo/lectura, pero asegurar estado de carga
          isLoading = false;
        }

        _safeNotify();
      }, onError: (error) {
        isLoading = false;
        _safeNotify();
      });
    }
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

  bool _isOfflineFromConnectivity(dynamic result) {
    if (result == null) return true;
    if (result is ConnectivityResult) {
      return result == ConnectivityResult.none;
    }
    if (result is List) {
      if (result.isEmpty) return true;
      return result.every((entry) => entry == ConnectivityResult.none);
    }
    return true;
  }

  Future<void> _startDriverLocationTracking() async {
    try {
      _foregroundTrackingService?.dispose();
      _foregroundTrackingService = TrackingService();

      final started = await _foregroundTrackingService!.iniciarTrackingConEnvio(
        userId: currentUserId,
        userType: 'conductor',
        solicitudId: solicitudId,
        distanceFilter: 1.0,
        timeInterval: 10,
        onLocationUpdate: (position) {
          try {
            final latLng = LatLng(position.latitude, position.longitude);
            // Forward device location into the viewmodel processing pipeline.
            unawaited(_onDriverPositionFromDevice(latLng));
          } catch (e) {
            if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] onLocationUpdate error: $e');
          }
        },
      );
      if (kDebugMode) {
        debugPrint('[TripRouteTrackingViewModel] TrackingService.iniciarTrackingConEnvio started: $started');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] Error starting foreground tracking: $e');
    }
  }

  Future<void> _onDriverPositionFromDevice(LatLng point) async {
    // If we have a persisted route, snap the marker to the nearest point
    // on the polyline so temporary GPS jumps don't move the marker off-route.
    if (routePoints.length >= 2) {
      final minDist = _mathService.minDistanceToPolylineMeters(point, routePoints);
      if (minDist <= 50.0) {
        final nearestIdx = _mathService.nearestPointIndex(point, routePoints);
        final snapped = routePoints[nearestIdx];
        conductorLatLng = snapped;
        debugPrint('[TripRouteTrackingViewModel] Snapped conductor to route index $nearestIdx (dist ${minDist.toStringAsFixed(1)} m)');
      } else {
        // Off-route by more than threshold: use raw point and trigger route rebuild.
        conductorLatLng = point;
        debugPrint('[TripRouteTrackingViewModel] Conductor off-route by ${minDist.toStringAsFixed(1)} m — will request route recalculation');
        // Throttle route recalculation to avoid calling routing repeatedly.
        final nowMs = DateTime.now();
        if (_lastRouteRecalcAt == null || nowMs.difference(_lastRouteRecalcAt!) > const Duration(seconds: 30)) {
          _lastRouteRecalcAt = nowMs;
          unawaited(_ensurePersistedRoute(forceRecalculate: true));
        }
      }
    } else {
      conductorLatLng = point;
    }

    _updateRemainingMetrics();
    _safeNotify();

    final now = DateTime.now();
    if (_lastDriverWriteAt != null &&
        now.difference(_lastDriverWriteAt!) < const Duration(seconds: 4)) {
      return;
    }

    if (_lastDriverSentPoint != null) {
      final moved = _mathService.haversineMeters(_lastDriverSentPoint!, point);
      if (moved < 1) {
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
      // When we snapped to the route, persist the snapped point so the
      // stored conductor position stays on the polyline. If we were off-route
      // we persist the raw GPS point.
      final toPersist = (routePoints.length >= 2 && conductorLatLng != null)
          ? conductorLatLng!
          : point;
      await _firebaseService.actualizarUbicacionConductorEnSolicitud(
        solicitudId: solicitudId,
        location: toPersist,
        timestampMs: now.millisecondsSinceEpoch,
        appendRouteHistory: true,
      );
      _lastDriverSentPoint = toPersist;
    } catch (_) {
      await _localCacheService.appendPendingConductorLocation(
        solicitudId: solicitudId,
        lat: point.latitude,
        lng: point.longitude,
        timestampMs: now.millisecondsSinceEpoch,
      );
    }

    // Keep using the persisted route while moving; avoid route API recalculation.
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
    estadoSolicitud = SolicitudEstado.normalize(
      ((data['estado'] ?? data['status']) ?? '').toString(),
    );

    final conductorMap = _asStringMap(data['conductor']);
    final clienteMap = _asStringMap(data['cliente']);
    final destinoMap = _asStringMap(data['destino']);

    // Solo actualizar conductorLatLng desde Firestore si estamos en la app del
    // conductor. En cliente preferimos mover el marcador localmente desde
    // el GPS del propio dispositivo.
    if (isConductor) {
      conductorLatLng = _extractPoint(conductorMap);
    }
    try {
      if (conductorLatLng != null) {
        debugPrint('[TripRouteTrackingViewModel] conductorLatLng set: ${conductorLatLng!.latitude}, ${conductorLatLng!.longitude}');
      } else {
        debugPrint('[TripRouteTrackingViewModel] conductorLatLng set: null');
      }
    } catch (_) {}
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
      final generated = await _routeService.fetchRoadPolyline(
        from: from,
        to: to,
      );
      debugPrint('[TripRouteTrackingViewModel] Generated route points: ${generated.length}');
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
        source: 'osrm',
        recalculatedByDeviation: forceRecalculate,
      );

      await _localCacheService.saveRoute(
        solicitudId: solicitudId,
        points: routePoints,
        distanceMeters: distance,
        etaSeconds: etaRemaining?.inSeconds,
      );
    } catch (_) {
      // Keep last known route if route refresh fails.
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  // ------------------ Cliente: tracking local para mover marcador -------------
  Future<void> _startClientLocationTracking() async {
    try {
      _foregroundTrackingService?.dispose();
      _foregroundTrackingService = TrackingService();

      final started = await _foregroundTrackingService!.iniciarTrackingConEnvio(
        userId: currentUserId,
        userType: 'cliente',
        solicitudId: solicitudId,
        distanceFilter: 1.0,
        timeInterval: 5,
        onLocationUpdate: (position) {
          try {
            final latLng = LatLng(position.latitude, position.longitude);
            // Move the car marker locally on the client device (no persistence)
            _onClientPositionFromDevice(latLng);
          } catch (e) {
            if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] client onLocationUpdate error: $e');
          }
        },
      );
      if (kDebugMode) {
        debugPrint('[TripRouteTrackingViewModel] Client tracking started: $started');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] Error starting client tracking: $e');
    }
  }

  void _onClientPositionFromDevice(LatLng point) {
    // Update the displayed car marker using the device GPS without writing
    // to Firestore or altering server-side conductor state.
    try {
      // If we have a route, snap to nearest route point for smoothness
      if (routePoints.length >= 2) {
        final minDist = _mathService.minDistanceToPolylineMeters(point, routePoints);
        if (minDist <= 50.0) {
          final nearestIdx = _mathService.nearestPointIndex(point, routePoints);
          final snapped = routePoints[nearestIdx];
          conductorLatLng = snapped;
        } else {
          conductorLatLng = point;
        }
      } else {
        conductorLatLng = point;
      }

      _updateRemainingMetrics();
      _safeNotify();
    } catch (e) {
      if (kDebugMode) debugPrint('[TripRouteTrackingViewModel] _onClientPositionFromDevice error: $e');
    }
  }

  void _updateRemainingMetrics() {
    final current = conductorLatLng;
    if (current == null || routePoints.length < 2) {
      distanceRemainingMeters = null;
      etaRemaining = null;
      conductorHeading = 0.0;
      return;
    }
    final remaining = _mathService.remainingDistanceMeters(
      current,
      routePoints,
    );
    distanceRemainingMeters = remaining;
    etaRemaining = _mathService.etaFromDistance(remaining);

    try {
      final nearest = _mathService.nearestPointIndex(current, routePoints);
      // Prefer next point for heading, otherwise previous.
      LatLng? target;
      if (nearest < routePoints.length - 1) {
        target = routePoints[nearest + 1];
      } else if (nearest > 0) {
        target = routePoints[nearest];
      }
      if (target != null) {
        conductorHeading = _mathService.bearingBetween(current, target);
      }
    } catch (_) {}
  }

  void _handleStateTransitions() {
    if (_completionHandled) return;

    final normalized = _normalizeEstado(estadoSolicitud);
    if (normalized != SolicitudEstado.completado) return;

    _completionHandled = true;
    isCompletingTrip = true;
    shouldNavigateToSummary = true;
  }

  String _normalizeEstado(String rawEstado) {
    return SolicitudEstado.normalize(rawEstado);
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
    try {
      _foregroundTrackingService?.dispose();
    } catch (_) {}
    super.dispose();
  }
}
