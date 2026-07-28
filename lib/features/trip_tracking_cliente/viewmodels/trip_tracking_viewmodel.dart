import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/conductor_movement_simulator.dart';
import '../controllers/trip_chat_controller.dart';
import '../services/trip_route_math_service.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/mensaje_model.dart';
import '../models/solicitud_model.dart';
import '../services/chat_service.dart';
import '../services/trip_tracking_firestore_service.dart';
import '../services/local_cache_service.dart';
import '../services/map_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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
       _localCacheService = localCacheService ?? LocalCacheService(),
       _chatController = TripChatController(
         solicitudId: solicitudId,
         currentUserId: currentUserId,
         chatService: chatService,
         localCacheService: localCacheService,
       ) {
    _movementEngine.onTick = _notifyTickThrottled;
    _movementEngine.onSnap = () {
      _safeNotify();
      unawaited(_updateRouteIfNeeded(forceRefresh: true));
    };
    _movementEngine.remainingRoutePointsNotifier.addListener(
      _onRemainingRouteChanged,
    );
    _chatController.onChanged = _safeNotify;
  }

  final String solicitudId;
  final String currentUserId;
  final String cancelledBy;

  final TripTrackingFirebaseService _firebaseService;
  final MapService _mapService;
  final TripRouteMathService _mathService = const TripRouteMathService();
  final LocalCacheService _localCacheService;

  /// Motor de animación/smoothing de la posición del conductor (timer 50ms,
  /// backlog, saltos grandes, snap-to-route). Ver
  /// `controllers/conductor_movement_simulator.dart`.
  final ConductorMovementSimulator _movementEngine =
      ConductorMovementSimulator();

  /// Chat del viaje (binding, cache, no-leídos, notificación). Ver
  /// `controllers/trip_chat_controller.dart`.
  final TripChatController _chatController;

  SolicitudModel? solicitud;
  double? distanceMeters;
  Duration? eta;

  List<MensajeModel> get messages => _chatController.messages;
  int get unreadCount => _chatController.unreadCount;

  bool isLoading = true;
  bool isUpdatingRoute = false;
  bool isCancelling = false;
  bool isOffline = false;

  MapFocusMode focusMode = MapFocusMode.clientOnly;

  String? errorText;

  StreamSubscription<SolicitudModel>? _solicitudSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _disposed = false;
  bool _proximityNotified = false;

  /// Notifiers de alta frecuencia (posición/heading/ruta restante) del motor
  /// de movimiento, expuestos tal cual para que la View pueda animar solo la
  /// capa del mapa sin reconstruir toda la pantalla. Ver comentario original
  /// en `ConductorMovementSimulator`: notificar por este medio evita 20
  /// rebuilds/seg de Scaffold+Card+overlays.
  ValueNotifier<LatLng?> get conductorPositionNotifier =>
      _movementEngine.positionNotifier;
  ValueNotifier<double> get conductorHeadingNotifier =>
      _movementEngine.headingNotifier;
  ValueNotifier<List<LatLng>> get routePointsNotifier =>
      _movementEngine.remainingRoutePointsNotifier;

  DateTime? _lastTickNotifyAt;
  static const _tickNotifyInterval = Duration(milliseconds: 400);

  // Distancia total de la ruta al calcularla por primera vez; junto con
  // `distanceMeters` (restante) permite derivar el progreso real 0..1 hacia
  // el punto de recogida para la barra direccional de la card.
  double? _initialRouteDistance;

  /// Progreso real (0..1) del conductor hacia el punto de recogida, para la
  /// barra direccional de `UserTripInfoCard` (antes era un shimmer decorativo
  /// sin relación con la posición real).
  double get pickupProgress {
    final total = _initialRouteDistance;
    if (total == null || total <= 0) return 0.0;
    final remaining = distanceMeters ?? total;
    final done = (total - remaining).clamp(0.0, total);
    return (done / total).clamp(0.0, 1.0);
  }

  LatLng? _lastFrom;
  LatLng? _lastTo;
  bool _routeCalculatedOnce = false;

  Future<void> init() async {
    await _restoreFromCache();
    await _bindConnectivity();
    _bindSolicitud();
    _chatController.bind();
  }

  /// Recalcula distancia/ETA cada vez que el motor de movimiento publica una
  /// nueva ruta restante (throttled a 200ms internamente, o forzado tras un
  /// fetch de ruta/snap). Reemplaza el cálculo que antes vivía duplicado en
  /// `_tickMovement`/`_snapConductorTo`.
  void _onRemainingRouteChanged() {
    final remaining = _movementEngine.remainingRoutePointsNotifier.value;
    final remainingDistance = _mapService.routeDistanceMeters(remaining);
    distanceMeters = remainingDistance;
    eta = _mapService.etaFromDistance(remainingDistance);
  }

  /// Notifica a los listeners "pesados" (Consumer de toda la pantalla) con
  /// throttle: el motor de movimiento tickea a 50ms pero la card/ETA/texto no
  /// necesitan refrescarse más rápido que esto para verse fluidos, y evita
  /// reconstruir Scaffold+GoogleMap+overlays 20 veces por segundo.
  void _notifyTickThrottled() {
    final now = DateTime.now();
    if (_lastTickNotifyAt != null &&
        now.difference(_lastTickNotifyAt!) < _tickNotifyInterval) {
      return;
    }
    _lastTickNotifyAt = now;
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
      _movementEngine.currentPosition ?? _rawConductorLatLng;

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
      final friendly =
          [pm.street?.trim(), pm.subLocality?.trim(), pm.locality?.trim()]
              .whereType<String>()
              .where((v) => v.isNotEmpty)
              .take(2)
              .join(', ')
              .trim();
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

  /// Cámara siempre anclada en la ubicación del cliente (foco principal),
  /// rotada hacia el conductor y con zoom que se ajusta según la distancia
  /// entre ambos: así se ve al conductor acercándose sobre el mapa sin
  /// perder de vista la posición del cliente.
  CameraPosition? getCameraPerspective() {
    final client = clienteLatLng;
    final driver = conductorLatLng;
    if (client == null || driver == null) return null;

    final bearing = _mathService.bearingBetween(client, driver);
    final distance = _mapService.distanceMeters(client, driver);

    return CameraPosition(
      target: client,
      bearing: bearing,
      tilt: 0.0,
      zoom: _zoomForDistance(distance),
    );
  }

  double _zoomForDistance(double meters) {
    if (meters <= 150) return 17.5;
    if (meters <= 300) return 16.8;
    if (meters <= 600) return 16.0;
    if (meters <= 1200) return 15.0;
    if (meters <= 2500) return 14.0;
    if (meters <= 5000) return 13.0;
    return 12.0;
  }

  Future<void> sendMessage(String text) => _chatController.sendMessage(text);

  Future<void> markChatAsRead() => _chatController.markAllAsRead();

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
            } catch (e, st) {
              ErrorReporter.report(e, st, reason: 'trip_tracking_viewmodel');
            }
            isLoading = false;
            errorText = null;
            _safeNotify();

            await _localCacheService.saveSolicitud(item);

            // ─── Actualización de ruta y heading ───

            await _updateRouteIfNeeded();
            _movementEngine.refreshHeading();
            _safeNotify();
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
      final raw = _rawConductorLatLng;
      if (_movementEngine.currentPosition == null && raw != null) {
        _movementEngine.restorePosition(raw);
      }
    }

    final cachedRoute = await _localCacheService.readRoute(solicitudId);
    if (cachedRoute != null && cachedRoute.points.length >= 2) {
      _movementEngine.restoreRemainingRoute(cachedRoute.points);
      _movementEngine.setFullRoute(_mathService.densifyPolyline(cachedRoute.points));
      distanceMeters = cachedRoute.distanceMeters;
      _initialRouteDistance = cachedRoute.distanceMeters;
      eta = cachedRoute.etaSeconds != null
          ? Duration(seconds: cachedRoute.etaSeconds!)
          : null;
    }

    await _chatController.restoreFromCache();

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

    if (isOffline && routePointsNotifier.value.length >= 2 && !forceRefresh) {
      return;
    }

    isUpdatingRoute = true;
    _safeNotify();

    try {
      final points = await _mapService.fetchRoadPolyline(from: from, to: to);
      final distance = _mapService.routeDistanceMeters(points);

      _movementEngine.setFullRoute(_mathService.densifyPolyline(points));
      final current = conductorLatLng ?? from;
      _movementEngine.publishRemainingRoute(current, force: true);
      final remainingDistance = _mapService.routeDistanceMeters(
        routePointsNotifier.value,
      );
      distanceMeters = remainingDistance > 0 ? remainingDistance : distance;
      // Nueva línea base de progreso: cada (re)cálculo de ruta (incluyendo
      // por desvío) reinicia el 100% de la barra direccional.
      _initialRouteDistance = distance;
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
    } catch (e, st) {
      // No rompe la UI: conserva la ultima ruta valida. Pero antes esto era
      // 100% silencioso — si Directions/OSRM fallaban, la traza (polyline)
      // simplemente no aparecía nunca y no había forma de saber por qué.
      developer.log(
        'Fallo al actualizar ruta (polyline no se actualizará esta vez): $e',
        name: 'TripTrackingViewModel',
        level: 1000,
      );
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'TripTrackingViewModel: fallo _updateRouteIfNeeded (sin ruta/polyline)',
      );
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  DateTime? _lastRouteRecalcAt;

  void _checkProximityNotification(LatLng conductorPos) {
    if (_proximityNotified) return;
    final client = clienteLatLng;
    if (client == null) return;
    final distancia = _mapService.distanceMeters(conductorPos, client);
    // Mismo radio que la notificación push de respaldo (Cloud Function
    // onConductorProximidadCliente) para que el aviso sea consistente sin
    // importar si la app está en primer o segundo plano.
    if (distancia <= 70) {
      _proximityNotified = true;
      NotificacionesServicio.instance.showNotification(
        id: 77701,
        title: 'Tu conductor está cerca',
        body: 'El conductor esta por llegar. ¡Prepárate para abordar!',
        payload:
            'soporte_chat', // payload genérico; redirige al inicio del cliente si toca
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
    final desvio = _movementEngine.distanceToRoute(next);
    final now = DateTime.now();
    final cooldownOk =
        _lastRouteRecalcAt == null ||
        now.difference(_lastRouteRecalcAt!).inSeconds >= 8;
    if (desvio != null && desvio > 40 && cooldownOk && !isOffline) {
      _lastRouteRecalcAt = now;
      unawaited(_updateRouteIfNeeded(forceRefresh: true));
    }

    _movementEngine.enqueueTarget(next);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void pauseForBackground() {
    _movementEngine.pause();
  }

  void resumeFromBackground() {
    final raw = _rawConductorLatLng;
    _movementEngine.resume(raw);
    if (raw == null) _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _solicitudSub?.cancel();
    _connectivitySub?.cancel();
    _chatController.dispose();
    _movementEngine.remainingRoutePointsNotifier.removeListener(
      _onRemainingRouteChanged,
    );
    _movementEngine.dispose();
    super.dispose();
  }
}
