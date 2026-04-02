import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/trip_route_math_service.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/mensaje_model.dart';
import '../models/solicitud_model.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import '../services/local_cache_service.dart';
import '../services/map_service.dart';

enum MapFocusMode { clientOnly, both }

class TripTrackingViewModel extends ChangeNotifier {
  // Notificaciones:
  // - Local notifications (gratis) para avisos en app activa.
  // - Para escenarios mas robustos en segundo plano/cross-device, se recomienda FCM
  //   (tambien con capa gratuita) o proveedores enterprise si se requiere SLA avanzado.
  TripTrackingViewModel({
    required this.solicitudId,
    required this.currentUserId,
    required this.cancelledBy,
    TripTrackingFirebaseService? firebaseService,
    MapService? mapService,
    ChatService? chatService,
    LocalCacheService? localCacheService,
  }) : _firebaseService = firebaseService ?? TripTrackingFirebaseService(),
       _mapService = mapService ?? MapService(),
       _chatService = chatService ?? ChatService(),
       _localCacheService = localCacheService ?? LocalCacheService();

  final String solicitudId;
  final String currentUserId;
  final String cancelledBy;

  final TripTrackingFirebaseService _firebaseService;
  final MapService _mapService;
  final TripRouteMathService _mathService = const TripRouteMathService();
  final ChatService _chatService;
  final LocalCacheService _localCacheService;

  SolicitudModel? solicitud;
  List<LatLng> routePoints = const [];
  double? distanceMeters;
  Duration? eta;

  List<MensajeModel> messages = const [];
  int unreadCount = 0;

  bool isLoading = true;
  bool isUpdatingRoute = false;
  bool isCancelling = false;
  bool isOffline = false;

  MapFocusMode focusMode = MapFocusMode.clientOnly;

  String? errorText;

  StreamSubscription<SolicitudModel>? _solicitudSub;
  StreamSubscription<List<MensajeModel>>? _messagesSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _disposed = false;
  bool _chatBootstrapped = false;

  // Heading (degrees) for the conductor marker; 0 = north, 90 = east.
  double conductorHeading = 0.0;

  // Smoothed marker state.
  LatLng? _smoothedConductorLatLng;
  final List<LatLng> _pendingConductorTargets = <LatLng>[];
  List<LatLng> _activePathPoints = const [];
  int _activePathIndex = 0;
  Timer? _movementTimer;
  double _movementSpeedMps = 8.0;
  LatLng? _lastRawConductor;
  DateTime? _lastRawConductorAt;

  LatLng? _lastFrom;
  LatLng? _lastTo;
  bool _routeCalculatedOnce = false;

  Future<void> init() async {
    await _restoreFromCache();
    await _bindConnectivity();
    _bindSolicitud();
    _bindMessages();
  }

  void _updateConductorHeading() {
    try {
      final current = conductorLatLng;
      if (current == null || routePoints.length < 2) {
        conductorHeading = 0.0;
        return;
      }

      final nearest = _mathService.nearestPointIndex(current, routePoints);
      LatLng? target;
      if (nearest < routePoints.length - 1) {
        target = routePoints[nearest + 1];
      } else if (nearest > 0) {
        target = routePoints[nearest];
      }
      if (target != null) {
        conductorHeading = _mathService.bearingBetween(current, target);
      }
    } catch (_) {
      conductorHeading = 0.0;
    }
    _safeNotify();
  }

  LatLng? get clienteLatLng {
    final c = solicitud?.cliente;
    if (c == null || !c.hasLocation) return null;
    return LatLng(c.lat!, c.lng!);
  }

  LatLng? get _rawConductorLatLng {
    final d = solicitud?.conductor;
    if (d == null || !d.hasLocation) return null;
    return LatLng(d.lat!, d.lng!);
  }

  LatLng? get conductorLatLng => _smoothedConductorLatLng ?? _rawConductorLatLng;

  bool get hasBothLocations => clienteLatLng != null && _rawConductorLatLng != null;

  String get distanciaTexto {
    final d = distanceMeters;
    if (d == null) return '--';
    return _mapService.formatDistance(d);
  }

  String get etaTexto {
    final e = eta;
    if (e == null) return '--';
    return _mapService.formatEta(e);
  }

  String get nombreCliente => solicitud?.cliente.nombre.isNotEmpty == true
      ? solicitud!.cliente.nombre
      : 'Cliente';

  String get nombreConductor => solicitud?.conductor.nombre.isNotEmpty == true
      ? solicitud!.conductor.nombre
      : 'Conductor';

  String get fotoUsuario {
    if (_isCurrentUserCliente) {
      return solicitud?.conductor.fotoUrl ?? '';
    }
    return solicitud?.cliente.fotoUrl ?? '';
  }

  String get nombreUsuarioCard {
    return _isCurrentUserCliente ? nombreConductor : nombreCliente;
  }

  String get fotoVehiculo {
    if (_isCurrentUserCliente) {
      return solicitud?.conductor.fotoVehiculoUrl ?? '';
    }
    return '';
  }

  String get placaVehiculo {
    if (_isCurrentUserCliente) {
      return solicitud?.conductor.placaVehiculo ?? '';
    }
    return '';
  }

  bool get _isCurrentUserCliente => solicitud?.cliente.id == currentUserId;

  Future<void> toggleMapFocusMode() async {
    focusMode = focusMode == MapFocusMode.clientOnly
        ? MapFocusMode.both
        : MapFocusMode.clientOnly;
    _safeNotify();
  }

  CameraPosition? getCameraPerspective() {
    final client = clienteLatLng;
    final driver = conductorLatLng;
    if (client == null || driver == null) return null;

    final bearing = _mathService.bearingBetween(client, driver);

    return CameraPosition(
      target: client,
      bearing: bearing,
      tilt: 0.0,
      zoom: 16.5,
    );
  }

  Future<void> sendMessage(String text) {
    return _chatService.sendMessage(
      solicitudId: solicitudId,
      senderId: currentUserId,
      texto: text,
    );
  }

  Future<void> markChatAsRead() async {
    if (messages.isEmpty) return;
    await _chatService.markAllAsRead(
      solicitudId: solicitudId,
      userId: currentUserId,
      messages: messages,
    );

    messages = messages
        .map(
          (m) => m.senderId == currentUserId
              ? m
              : MensajeModel(
                  id: m.id,
                  senderId: m.senderId,
                  texto: m.texto,
                  timestamp: m.timestamp,
                  readBy: {...m.readBy, currentUserId: true},
                ),
        )
        .toList(growable: false);
    _computeUnreadCount();
    _safeNotify();
  }

  Future<void> cancelSolicitud() async {
    if (isCancelling) return;

    isCancelling = true;
    _safeNotify();

    try {
      await _firebaseService.cancelarSolicitud(
        solicitudId: solicitudId,
        cancelledBy: cancelledBy,
      );
      await _localCacheService.clearSolicitudData(solicitudId);
    } finally {
      isCancelling = false;
      _safeNotify();
    }
  }

  void _bindSolicitud() {
    _solicitudSub?.cancel();
    _solicitudSub = _firebaseService
        .watchSolicitud(solicitudId)
        .listen(
          (item) async {
            solicitud = item;
            _handleConductorLocationUpdate(item);
            try {
              final d = solicitud?.conductor;
              if (d != null && d.hasLocation) {
                debugPrint('[TripTrackingViewModel] Conductor location update: ${d.lat}, ${d.lng}');
              } else {
                debugPrint('[TripTrackingViewModel] Conductor location update: none');
              }
            } catch (_) {}
            isLoading = false;
            errorText = null;
            _safeNotify();

            await _localCacheService.saveSolicitud(item);

            // ─── Actualizacion de ruta y heading ───

                  await _updateRouteIfNeeded();
                  _updateConductorHeading();
          },
          onError: (error) async {
            isLoading = false;

            final cached = await _localCacheService.readSolicitud(solicitudId);
            if (cached != null) {
              solicitud = cached;
              errorText = 'Sin conexion: mostrando datos en cache';
            } else {
              errorText = 'No se pudo cargar la solicitud: $error';
            }

            _safeNotify();
          },
        );
  }

  void _bindMessages() {
    _messagesSub?.cancel();
    _messagesSub = _chatService
        .watchMessages(solicitudId)
        .listen(
          (incoming) async {
            if (_chatBootstrapped) {
              final previousIds = messages.map((m) => m.id).toSet();
              final newIncoming = incoming.where(
                (m) =>
                    !previousIds.contains(m.id) && m.senderId != currentUserId,
              );

              for (final item in newIncoming) {
                await _showMessageNotification(item.texto);
              }
            } else {
              _chatBootstrapped = true;
            }

            messages = incoming;
            _computeUnreadCount();

            await _localCacheService.saveMessages(
              solicitudId: solicitudId,
              messages: incoming,
            );

            _safeNotify();
          },
          onError: (error) async {
            final cachedMessages = await _localCacheService.readMessages(
              solicitudId,
            );
            if (cachedMessages.isNotEmpty) {
              messages = cachedMessages;
              _computeUnreadCount();
              _safeNotify();
            }
          },
        );
  }

  Future<void> _bindConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    isOffline = _isOfflineFromConnectivity(result);

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final nextOffline = _isOfflineFromConnectivity(result);
      if (isOffline == nextOffline) return;
      isOffline = nextOffline;
      _safeNotify();

      if (!isOffline) {
        _updateRouteIfNeeded(forceRefresh: true);
      }
    });
  }

  bool _isOfflineFromConnectivity(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((item) => item == ConnectivityResult.none);
  }

  Future<void> _restoreFromCache() async {
    final cachedSolicitud = await _localCacheService.readSolicitud(solicitudId);
    if (cachedSolicitud != null) {
      solicitud = cachedSolicitud;
      isLoading = false;
      _smoothedConductorLatLng ??= _rawConductorLatLng;
    }

    final cachedRoute = await _localCacheService.readRoute(solicitudId);
    if (cachedRoute != null && cachedRoute.points.length >= 2) {
      routePoints = cachedRoute.points;
      distanceMeters = cachedRoute.distanceMeters;
      eta = cachedRoute.etaSeconds != null
          ? Duration(seconds: cachedRoute.etaSeconds!)
          : null;
    }

    final cachedMessages = await _localCacheService.readMessages(solicitudId);
    if (cachedMessages.isNotEmpty) {
      messages = cachedMessages;
      _computeUnreadCount();
    }

    _safeNotify();
  }

  Future<void> _updateRouteIfNeeded({bool forceRefresh = false}) async {
    if (!hasBothLocations || isUpdatingRoute) return;

    // Si ya calculamos la ruta una vez, no volver a calcular a menos que se
    // solicite explícitamente con `forceRefresh`.
    if (_routeCalculatedOnce && !forceRefresh) return;

    final from = _rawConductorLatLng!;
    final to = clienteLatLng!;

    final shouldRefresh =
        _lastFrom == null ||
        _lastTo == null ||
        _mapService.distanceMeters(_lastFrom!, from) > 20 ||
        _mapService.distanceMeters(_lastTo!, to) > 20;

    if (!forceRefresh && !shouldRefresh) return;

    if (isOffline && routePoints.length >= 2 && !forceRefresh) {
      return;
    }

    isUpdatingRoute = true;
    _safeNotify();

    try {
      final points = await _mapService.fetchRoadPolyline(from: from, to: to);
      final distance = _mapService.routeDistanceMeters(points);

      routePoints = points;
      distanceMeters = distance;
      eta = _mapService.etaFromDistance(distance);

      await _localCacheService.saveRoute(
        solicitudId: solicitudId,
        points: points,
        distanceMeters: distance,
        etaSeconds: eta?.inSeconds,
      );

      _lastFrom = from;
      _lastTo = to;
      _routeCalculatedOnce = true;
    } catch (_) {
      // No rompe la UI: conserva la ultima ruta valida.
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  Future<void> _showMessageNotification(String body) async {
    try {
      await NotificacionesServicio.instance.showChatNotification(
        senderName: '\u{1F4AC} Nuevo mensaje del conductor',
        message: body,
      );
    } catch (_) {
      // Sin bloquear la UX si notificaciones no estan disponibles.
    }
  }

  void _computeUnreadCount() {
    unreadCount = messages
        .where((m) => m.senderId != currentUserId && !m.isReadBy(currentUserId))
        .length;
  }

  void _handleConductorLocationUpdate(SolicitudModel item) {
    final d = item.conductor;
    if (d == null || !d.hasLocation) return;
    final next = LatLng(d.lat!, d.lng!);
    _enqueueConductorTarget(next);
  }

  void _enqueueConductorTarget(LatLng target) {
    final now = DateTime.now();
    if (_lastRawConductor != null && _lastRawConductorAt != null) {
      final elapsedMs = now.difference(_lastRawConductorAt!).inMilliseconds;
      if (elapsedMs > 0) {
        final distance = _mapService.distanceMeters(_lastRawConductor!, target);
        final speed = distance / (elapsedMs / 1000.0);
        _movementSpeedMps = speed.clamp(3.0, 18.0);
      }
    }
    _lastRawConductor = target;
    _lastRawConductorAt = now;

    if (_smoothedConductorLatLng == null) {
      _smoothedConductorLatLng = target;
      _safeNotify();
      return;
    }

    if (_pendingConductorTargets.length >= 3) {
      _pendingConductorTargets[_pendingConductorTargets.length - 1] = target;
    } else {
      _pendingConductorTargets.add(target);
    }

    _ensureMovementTimer();
  }

  void _ensureMovementTimer() {
    if (_movementTimer != null) return;
    _movementTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tickMovement(),
    );
  }

  void _prepareActivePath(LatLng from, LatLng to) {
    if (routePoints.length < 2) {
      _activePathPoints = <LatLng>[to];
      _activePathIndex = 0;
      return;
    }

    final startIdx = _mathService.nearestPointIndex(from, routePoints);
    final endIdx = _mathService.nearestPointIndex(to, routePoints);

    if (startIdx <= endIdx) {
      final segment = routePoints.sublist(startIdx, endIdx + 1);
      _activePathPoints = <LatLng>[...segment, to];
    } else {
      final segment = routePoints.sublist(endIdx, startIdx + 1).reversed;
      _activePathPoints = <LatLng>[...segment, to];
    }

    _activePathIndex = 0;
  }

  void _tickMovement() {
    if (_smoothedConductorLatLng == null) {
      _stopMovement();
      return;
    }

    if (_activePathPoints.isEmpty) {
      if (_pendingConductorTargets.isEmpty) {
        _stopMovement();
        return;
      }
      _prepareActivePath(_smoothedConductorLatLng!, _pendingConductorTargets.first);
    }

    final stepMeters = _movementSpeedMps * 0.05;
    var remaining = stepMeters;
    var current = _smoothedConductorLatLng!;

    while (remaining > 0 && _activePathIndex < _activePathPoints.length) {
      final next = _activePathPoints[_activePathIndex];
      final segmentDistance = _mapService.distanceMeters(current, next);

      if (segmentDistance <= 0.1) {
        current = next;
        _activePathIndex += 1;
        continue;
      }

      if (remaining >= segmentDistance) {
        current = next;
        remaining -= segmentDistance;
        _activePathIndex += 1;
      } else {
        final t = remaining / segmentDistance;
        current = LatLng(
          current.latitude + (next.latitude - current.latitude) * t,
          current.longitude + (next.longitude - current.longitude) * t,
        );
        remaining = 0;
      }
    }

    _smoothedConductorLatLng = current;
    _updateConductorHeading();

    if (_activePathIndex >= _activePathPoints.length) {
      if (_pendingConductorTargets.isNotEmpty) {
        _pendingConductorTargets.removeAt(0);
      }
      _activePathPoints = const [];
      _activePathIndex = 0;
    }
  }

  void _stopMovement() {
    _movementTimer?.cancel();
    _movementTimer = null;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _solicitudSub?.cancel();
    _messagesSub?.cancel();
    _connectivitySub?.cancel();
    _movementTimer?.cancel();
    super.dispose();
  }
}
