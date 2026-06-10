import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/trip_route_math_service.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/mensaje_model.dart';
import '../models/solicitud_model.dart';
import '../services/chat_service.dart';
import '../services/trip_tracking_firestore_service.dart';
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
  bool _proximityNotified = false;

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
  List<LatLng> _fullRoutePoints = const [];
  int _routeProgressIndex = 0;

  Future<void> init() async {
    await _restoreFromCache();
    await _bindConnectivity();
    _bindSolicitud();
    _bindMessages();
  }

  void _updateConductorHeading() {
    try {
      final current = conductorLatLng;
      final headingPoints = _fullRoutePoints.length >= 2
          ? _fullRoutePoints
          : routePoints;
      if (current == null || headingPoints.length < 2) {
        conductorHeading = 0.0;
        return;
      }

      final nearest = _nearestForwardIndex(current, headingPoints);
      LatLng? target;
      final lookAhead = nearest + 3;
      if (lookAhead < headingPoints.length) {
        target = headingPoints[lookAhead];
      } else if (nearest < headingPoints.length - 1) {
        target = headingPoints[nearest + 1];
      } else if (nearest > 0) {
        target = headingPoints[nearest];
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

  LatLng? get conductorLatLng =>
      _smoothedConductorLatLng ?? _rawConductorLatLng;

  bool get hasBothLocations =>
      clienteLatLng != null && _rawConductorLatLng != null;

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

  // Datos extra para el detalle del viaje.
  double get calificacionConductor => solicitud?.conductor.calificacion ?? 0;
  int get totalCalificacionesConductor =>
      solicitud?.conductor.totalCalificaciones ?? 0;
  String get destinoDireccion => solicitud?.destinoDireccion ?? '';
  double get valorServicio => solicitud?.valorServicio ?? 0;
  String get metodoPago => solicitud?.metodoPago ?? '';
  String get direccionCliente => solicitud?.cliente.direccion ?? '';

  String? _direccionClienteResuelta;
  bool _resolvingDireccionCliente = false;

  /// Ubicación del cliente para mostrar ("Tu ubicación") en TEXTO (no coords):
  /// dirección guardada si existe, si no la dirección resuelta por geocoding.
  String get tuUbicacionTexto {
    final dir = direccionCliente.trim();
    if (dir.isNotEmpty) return dir;
    final resuelta = _direccionClienteResuelta?.trim() ?? '';
    if (resuelta.isNotEmpty) return resuelta;
    return clienteLatLng != null
        ? 'Obteniendo dirección...'
        : 'Ubicación no disponible';
  }

  /// Geocoding inverso de la ubicación del cliente → dirección legible.
  Future<void> _resolverDireccionCliente() async {
    if (_resolvingDireccionCliente || _direccionClienteResuelta != null) return;
    if (direccionCliente.trim().isNotEmpty) return;
    final p = clienteLatLng;
    if (p == null) return;
    _resolvingDireccionCliente = true;
    try {
      final placemarks = await placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      if (placemarks.isEmpty) return;
      final pm = placemarks.first;
      final friendly = [
        pm.street?.trim(),
        pm.subLocality?.trim(),
        pm.locality?.trim(),
      ].whereType<String>().where((v) => v.isNotEmpty).take(2).join(', ').trim();
      if (friendly.isNotEmpty) {
        _direccionClienteResuelta = friendly;
        _safeNotify();
      }
    } catch (_) {
      // Falla geocoding: el getter muestra "Obteniendo dirección...".
    } finally {
      _resolvingDireccionCliente = false;
    }
  }

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
            unawaited(_resolverDireccionCliente());
            _handleConductorLocationUpdate(item);
            try {
              final d = solicitud?.conductor;
              if (d != null && d.hasLocation) {
                debugPrint(
                  '[TripTrackingViewModel] Conductor location update: ${d.lat}, ${d.lng}',
                );
              } else {
                debugPrint(
                  '[TripTrackingViewModel] Conductor location update: none',
                );
              }
            } catch (_) {}
            isLoading = false;
            errorText = null;
            _safeNotify();

            await _localCacheService.saveSolicitud(item);

            // ─── Actualización de ruta y heading ───

            await _updateRouteIfNeeded();
            _updateConductorHeading();
          },
          onError: (error) async {
            isLoading = false;

            final cached = await _localCacheService.readSolicitud(solicitudId);
            if (cached != null) {
              solicitud = cached;
              errorText = 'Sin conexión: mostrando datos en caché';
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
      _fullRoutePoints = _densifyPolyline(cachedRoute.points);
      _routeProgressIndex = 0;
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

      _fullRoutePoints = _densifyPolyline(points);
      _routeProgressIndex = 0;
      final current = conductorLatLng ?? from;
      routePoints = _buildRemainingRoutePoints(current);
      final remainingDistance = _mapService.routeDistanceMeters(routePoints);
      distanceMeters = remainingDistance > 0 ? remainingDistance : distance;
      eta = _mapService.etaFromDistance(distanceMeters!);

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

  DateTime? _lastRouteRecalcAt;

  void _checkProximityNotification(LatLng conductorPos) {
    if (_proximityNotified) return;
    final client = clienteLatLng;
    if (client == null) return;
    final distancia = _mapService.distanceMeters(conductorPos, client);
    if (distancia <= 50) {
      _proximityNotified = true;
      NotificacionesServicio.instance.showNotification(
        id: 77701,
        title: 'Tu conductor está cerca',
        body: 'El conductor esta por llegar. ¡Prepárate para abordar!',
        payload: 'soporte_chat', // payload genérico; redirige al inicio del cliente si toca
      );
    }
  }

  void _handleConductorLocationUpdate(SolicitudModel item) {
    final d = item.conductor;
    if (!d.hasLocation) return;
    final next = LatLng(d.lat!, d.lng!);

    _checkProximityNotification(next);

    // Desvío: si el conductor se aleja >40 m de la ruta trazada, recalcular la
    // ruta con la API (con cooldown para no spamear). El cliente verá la nueva
    // trayectoria de su conductor.
    final desvio = _distanceToRoute(next);
    final now = DateTime.now();
    final cooldownOk =
        _lastRouteRecalcAt == null ||
        now.difference(_lastRouteRecalcAt!).inSeconds >= 8;
    if (desvio != null && desvio > 40 && cooldownOk && !isOffline) {
      _lastRouteRecalcAt = now;
      unawaited(_updateRouteIfNeeded(forceRefresh: true));
    }

    _enqueueConductorTarget(next);
  }

  /// Distancia mínima (m) del punto a la polilínea de ruta (vértice más cercano,
  /// suficiente porque la ruta está densificada).
  double? _distanceToRoute(LatLng p) {
    final source = _fullRoutePoints.length >= 2 ? _fullRoutePoints : routePoints;
    if (source.length < 2) return null;
    double min = double.infinity;
    for (final pt in source) {
      final d = _mapService.distanceMeters(p, pt);
      if (d < min) min = d;
    }
    return min.isFinite ? min : null;
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

    final snappedTarget = _snapTargetToRouteForward(target);

    if (_pendingConductorTargets.isNotEmpty) {
      final lastQueued = _pendingConductorTargets.last;
      final delta = _mapService.distanceMeters(lastQueued, snappedTarget);
      if (delta < 1.2) {
        return;
      }
    }

    if (_pendingConductorTargets.isEmpty && _smoothedConductorLatLng != null) {
      final deltaFromCurrent = _mapService.distanceMeters(
        _smoothedConductorLatLng!,
        snappedTarget,
      );
      if (deltaFromCurrent < 1.2) {
        return;
      }
    }

    // Encola cada update para reproducir correctamente la trayectoria.
    _pendingConductorTargets.add(snappedTarget);

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
    final source = _fullRoutePoints.length >= 2
        ? _fullRoutePoints
        : routePoints;
    if (source.length < 2) {
      _activePathPoints = <LatLng>[to];
      _activePathIndex = 0;
      return;
    }

    final startIdx = _mathService.nearestPointIndex(from, source);
    final endIdx = _mathService.nearestPointIndex(to, source);

    if (startIdx <= endIdx) {
      final segment = source.sublist(startIdx, endIdx + 1);
      _activePathPoints = <LatLng>[...segment, to];
    } else {
      final segment = source.sublist(endIdx, startIdx + 1).reversed;
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
      _prepareActivePath(
        _smoothedConductorLatLng!,
        _pendingConductorTargets.first,
      );
    }

    var current = _smoothedConductorLatLng!;
    final effectiveSpeed = _effectiveSpeedForBacklog(current);
    final stepMeters = effectiveSpeed * 0.05;
    var remaining = stepMeters;

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
    routePoints = _buildRemainingRoutePoints(current);
    final remainingDistance = _mapService.routeDistanceMeters(routePoints);
    distanceMeters = remainingDistance;
    eta = _mapService.etaFromDistance(remainingDistance);
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

  double _effectiveSpeedForBacklog(LatLng current) {
    var speed = _movementSpeedMps;
    final backlog = _pendingConductorTargets.length;

    if (backlog >= 2) {
      speed *= (1.0 + (backlog - 1) * 0.35).clamp(1.0, 2.8);
    }

    if (backlog > 0) {
      final lagDistance = _mapService.distanceMeters(
        current,
        _pendingConductorTargets.first,
      );
      if (lagDistance > 70) {
        speed *= 1.5;
      } else if (lagDistance > 40) {
        speed *= 1.3;
      } else if (lagDistance > 20) {
        speed *= 1.15;
      }
    }

    return speed.clamp(3.0, 28.0);
  }

  LatLng _snapTargetToRouteForward(LatLng target) {
    final source = _fullRoutePoints;
    if (source.length < 2 || _smoothedConductorLatLng == null) {
      return target;
    }

    final start = _routeProgressIndex.clamp(0, source.length - 1);
    final end = (start + 240) < source.length
        ? (start + 240)
        : (source.length - 1);
    var nearest = start;
    var best = double.infinity;

    for (var i = start; i <= end; i++) {
      final p = source[i];
      final dist = _mapService.distanceMeters(target, p);
      if (dist < best) {
        best = dist;
        nearest = i;
      }
    }

    if (best > 80) {
      return target;
    }

    if (nearest > _routeProgressIndex) {
      _routeProgressIndex = nearest;
    }

    return source[_routeProgressIndex];
  }

  List<LatLng> _buildRemainingRoutePoints(LatLng current) {
    final source = _fullRoutePoints;
    if (source.length < 2) {
      return source;
    }

    final nearest = _nearestForwardIndex(current, source);
    if (nearest >= source.length - 1) {
      return <LatLng>[current, source.last];
    }

    final tail = source.sublist(nearest + 1);
    return <LatLng>[current, ...tail];
  }

  int _nearestForwardIndex(LatLng current, List<LatLng> source) {
    if (source.isEmpty) return 0;
    final nearest = _mathService.nearestPointIndex(current, source);
    if (nearest > _routeProgressIndex) {
      _routeProgressIndex = nearest;
    }
    if (_routeProgressIndex >= source.length) {
      _routeProgressIndex = source.length - 1;
    }
    return _routeProgressIndex;
  }

  List<LatLng> _densifyPolyline(List<LatLng> points) {
    if (points.length < 2) return points;
    const stepMeters = 6.0;
    final dense = <LatLng>[points.first];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segment = _mapService.distanceMeters(a, b);
      if (segment <= stepMeters) {
        dense.add(b);
        continue;
      }

      final steps = (segment / stepMeters).floor();
      for (var s = 1; s <= steps; s++) {
        final t = s / (steps + 1);
        dense.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
      }
      dense.add(b);
    }

    return dense;
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
