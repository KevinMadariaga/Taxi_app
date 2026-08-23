import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/cancelar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/confirmar_voy_en_camino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/controladores/chat_controller.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/features/trip_tracking_cliente/controllers/conductor_movement_simulator.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/local_cache_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_route_math_service.dart';

/// LA clase del cliente: reemplaza `TripTrackingViewModel`
/// (`asignado`→`en camino`) y `RutaClienteDestinoViewModel`
/// (`en ruta`→`completado`), cubriendo el viaje completo en un solo
/// `ChangeNotifier`.
///
/// El motor de animación (`ConductorMovementSimulator`) se inyecta tal
/// cual, sin tocar su lógica interna — ya resuelve exactamente lo pedido:
/// movimiento asíncrono del marcador trazado sobre la ruta real, con snap
/// a calle y manejo de saltos/gaps de GPS.
class ViajeClienteViewModel extends ChangeNotifier {
  ViajeClienteViewModel({
    required this.viajeId,
    required this.clienteId,
    required WatchViajeUseCase watchViaje,
    required ConfirmarVoyEnCaminoUseCase confirmarVoyEnCamino,
    required CancelarViajeUseCase cancelarViaje,
    required RutaDatasource rutaDatasource,
    ChatController? chatController,
    ConductorMovementSimulator? movementEngine,
    LocalCacheService? localCacheService,
  }) : _watchViaje = watchViaje,
       _confirmarVoyEnCamino = confirmarVoyEnCamino,
       _cancelarViaje = cancelarViaje,
       _ruta = rutaDatasource,
       _movementEngine = movementEngine ?? ConductorMovementSimulator(),
       _localCache = localCacheService ?? LocalCacheService(),
       chat =
           chatController ??
           ChatController(
             viajeId: viajeId,
             currentUserId: clienteId,
             otherPartyLabel: 'conductor',
           );

  final String viajeId;
  final String clienteId;

  final WatchViajeUseCase _watchViaje;
  final ConfirmarVoyEnCaminoUseCase _confirmarVoyEnCamino;
  final CancelarViajeUseCase _cancelarViaje;
  final RutaDatasource _ruta;
  final ConductorMovementSimulator _movementEngine;
  final TripRouteMathService _mathService = const TripRouteMathService();
  final LocalCacheService _localCache;

  final ChatController chat;

  ValueNotifier<LatLng?> get conductorPositionNotifier =>
      _movementEngine.positionNotifier;
  ValueNotifier<double> get conductorHeadingNotifier =>
      _movementEngine.headingNotifier;
  ValueNotifier<List<LatLng>> get routePointsNotifier =>
      _movementEngine.remainingRoutePointsNotifier;

  void pauseMovimientoConductor() => _movementEngine.pause();

  void resumeMovimientoConductor() =>
      _movementEngine.resume(conductorLatLngCrudo);

  ViajeEntity? viaje;
  bool isLoading = true;
  bool isUpdatingRoute = false;
  bool isCancelling = false;
  String? errorText;

  double? distanceMeters;
  Duration? eta;
  double _initialRouteDistance = 0;

  /// Se incrementa cada vez que `_updateRouteIfNeeded` recalcula una ruta
  /// válida contra el servicio de mapas. La screen lo usa para saber cuándo
  /// la ruta hacia el nuevo tramo (recogida→destino) ya está lista y
  /// reencuadrar la cámara, en vez de hacerlo en el instante del cambio de
  /// estado (cuando la polilínea todavía es la vieja).
  int rutaVersion = 0;

  /// Visible cuando el conductor reportó llegada (estado `en espera`) — el
  /// cliente confirma "Voy en camino" acá. El timeout de 3 min que cancela
  /// el viaje por falta de respuesta lo escribe el lado conductor
  /// (`ViajeConductorViewModel`); acá el conteo es solo informativo.
  bool waitingModalVisible = false;
  bool isConfirmingVoyEnCamino = false;
  final ValueNotifier<int> waitingRemainingSeconds = ValueNotifier<int>(180);

  StreamSubscription<ViajeEntity>? _viajeSub;

  /// Encadena el procesamiento de cada snapshot de Firestore: sin esto, dos
  /// snapshots seguidos podían solaparse en la mitad del `await` de
  /// `_handleEstadoTransition` (recálculo de ruta contra la API) — el que
  /// llegaba después "adelantaba" al anterior aplicando su posición del
  /// conductor antes de que el más viejo terminara, y el marcador saltaba
  /// hacia atrás justo al arrancar el tramo al destino (los pings de GPS
  /// son más frecuentes justo ahí). `.listen((incoming) async {...})` NO
  /// serializa por sí solo: Dart entrega el siguiente evento del stream en
  /// cuanto el callback anterior cede el control en su primer `await`.
  Future<void> _procesandoSnapshot = Future.value();
  Timer? _waitingTimer;
  String? _lastEstado;
  bool _disposed = false;
  DateTime? _lastTickNotifyAt;
  bool _routeCalculatedOnce = false;
  LatLng? _lastFrom;
  LatLng? _lastTo;
  DateTime? _lastRouteRecalcAt;
  bool _proximityNotified = false;

  LatLng? get clienteLatLng => viaje?.cliente.ubicacion;
  LatLng? get conductorLatLngCrudo => viaje?.conductor.ubicacion;

  /// Hacia dónde va el conductor AHORA: el punto de recogida mientras va a
  /// buscar al pasajero, y el destino una vez arrancó el viaje.
  ///
  /// Antes la ruta apuntaba siempre a `clienteLatLng`, así que una vez en
  /// `en ruta` el mapa, la polilínea, el ETA y la barra de progreso del
  /// pasajero seguían señalando su propia dirección de recogida durante todo
  /// el trayecto. Mismo criterio que `objetivoActual` en el ViewModel del
  /// conductor. Si el viaje no tiene destino con coordenadas, se mantiene la
  /// recogida como objetivo en vez de quedarse sin ruta.
  LatLng? get objetivoActual {
    final v = viaje;
    if (v == null) return null;
    if (v.estado == SolicitudEstado.enRuta) {
      return v.destino.ubicacion ?? v.cliente.ubicacion;
    }
    return v.cliente.ubicacion;
  }

  bool get hasBothLocations =>
      objetivoActual != null && conductorLatLngCrudo != null;

  String get distanceText =>
      distanceMeters == null ? '--' : _ruta.formatearDistancia(distanceMeters!);
  String get etaText => eta == null ? '--' : _ruta.formatearEta(eta!);

  /// Progreso real (0..1) hacia el punto de recogida — alimenta
  /// `BarraProgresoDireccional`.
  double get pickupProgress {
    if (_initialRouteDistance <= 0) return 0.0;
    final restante = distanceMeters ?? _initialRouteDistance;
    final avance = (_initialRouteDistance - restante) / _initialRouteDistance;
    return avance.clamp(0.0, 1.0);
  }

  String get conductorNombre {
    final n = viaje?.conductor.nombre ?? '';
    return n.isNotEmpty ? n : 'Conductor';
  }

  String get conductorFotoUrl => viaje?.conductor.fotoUrl ?? '';
  String get vehiculoFotoUrl => viaje?.conductor.fotoVehiculoUrl ?? '';
  String get placaVehiculo => viaje?.conductor.placaVehiculo ?? '';
  double get calificacionConductor => viaje?.conductor.calificacion ?? 0;
  bool get isMoto => viaje?.isMoto ?? false;

  Future<void> init() async {
    // El motor de movimiento dispara `onTick` cada 50ms mientras el marcador
    // está en curso: se usa para refrescar `distanceMeters`/`pickupProgress`
    // sin llamar a la API de rutas, con un notify throttleado (si no, son
    // ~20 rebuilds/s de la card entera). `onSnap` cubre saltos grandes o el
    // resume tras background, donde además de recalcular distancia liviana
    // hace falta un notify inmediato.
    _movementEngine.onTick = _onMovimientoTick;
    _movementEngine.onSnap = () {
      _actualizarDistanciaLiviana();
      _lastTickNotifyAt = DateTime.now();
      _safeNotify();
    };
    await _restoreFromCache();
    _bindViaje();
    chat.onChanged = () => _safeNotify();
    chat.bind();
  }

  void _onMovimientoTick() {
    _actualizarDistanciaLiviana();
    final now = DateTime.now();
    if (_lastTickNotifyAt != null &&
        now.difference(_lastTickNotifyAt!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastTickNotifyAt = now;
    _safeNotify();
  }

  /// Última lista de `routePointsNotifier` sobre la que se calculó
  /// `distanceMeters` — el motor solo reasigna esa lista (referencia nueva)
  /// cuando rearma la ruta restante, como máximo cada 200ms
  /// (`_rebuildRemainingRoute`). Sin este cache, el tick de 50ms recorría
  /// esa misma lista sin cambios ~3 de cada 4 veces: trabajo O(n) real
  /// desperdiciado en el hilo principal, justo con la ruta más larga
  /// (recién arrancado el tramo).
  List<LatLng>? _ultimaRutaMedida;

  /// Recalcula `distanceMeters` contra la ruta restante que el motor ya
  /// publica, sin llamar a la API de rutas. Equivalente del lado cliente a
  /// `_actualizarProgresoLiviano` del conductor
  /// (`ViajeConductorViewModel`), pero fiel a la ruta (no haversine) porque
  /// acá sí tenemos la polilínea restante actualizada tick a tick.
  void _actualizarDistanciaLiviana() {
    final restantes = routePointsNotifier.value;
    if (restantes.length >= 2) {
      if (identical(restantes, _ultimaRutaMedida)) return;
      _ultimaRutaMedida = restantes;
      distanceMeters = _ruta.distanciaRuta(restantes);
      return;
    }
    _ultimaRutaMedida = null;
    final pos = conductorPositionNotifier.value;
    final objetivo = objetivoActual;
    if (pos != null && objetivo != null) {
      distanceMeters = _mathService.haversineMeters(pos, objetivo);
    }
  }

  /// Restaura la última ruta calculada desde disco antes de que llegue el
  /// primer snapshot de Firestore — evita mapa en blanco unos segundos si
  /// la app se abrió sin conexión o el listener tarda en conectar.
  /// Se sobreescribe apenas llega el primer dato real (`_updateRouteIfNeeded`
  /// no reusa esto si ya hay ruta calculada en la sesión actual).
  Future<void> _restoreFromCache() async {
    final cached = await _localCache.readRoute(viajeId);
    if (cached == null || cached.points.length < 2) return;

    _movementEngine.setFullRoute(_mathService.densifyPolyline(cached.points));
    distanceMeters = cached.distanceMeters;
    _initialRouteDistance = cached.distanceMeters ?? 0;
    eta = cached.etaSeconds != null
        ? Duration(seconds: cached.etaSeconds!)
        : null;
    _safeNotify();
  }

  void _bindViaje() {
    _viajeSub?.cancel();
    _viajeSub = _watchViaje(viajeId).listen(
      (incoming) {
        // Encadenado sobre `_procesandoSnapshot`, no invocado directo: así
        // el snapshot siguiente espera a que termine el anterior en vez de
        // solaparse en su `await` (ver el comentario del campo).
        _procesandoSnapshot = _procesandoSnapshot
            .then((_) => _procesarSnapshot(incoming))
            .catchError((Object e, StackTrace st) {
              developer.log(
                'Error procesando snapshot: $e',
                name: 'ViajeClienteViewModel',
                level: 1000,
              );
            });
      },
      onError: (error) {
        isLoading = false;
        errorText = 'No se pudo cargar el viaje: $error';
        _safeNotify();
      },
    );
  }

  Future<void> _procesarSnapshot(ViajeEntity incoming) async {
    if (_disposed) return;
    viaje = incoming;
    isLoading = false;
    errorText = null;
    _safeNotify();

    // Se espera la transición ANTES de procesar la ubicación: si el viaje
    // acaba de pasar a `en ruta`, la transición dispara un recálculo de
    // ruta hacia el destino, y sin esperarlo acá `_handleConductorLocationUpdate`
    // proyectaba (`snapForwardToRoute`) la posición del conductor contra la
    // polilínea vieja de recogida en el primer ping tras el cambio de tramo.
    await _handleEstadoTransition(incoming.estado);
    if (_disposed) return;
    _handleConductorLocationUpdate(incoming);
    await _updateRouteIfNeeded();

    if (SolicitudEstado.isTerminal(incoming.estado)) {
      unawaited(_localCache.clearSolicitudData(viajeId));
    }
  }

  Future<void> _handleEstadoTransition(String estado) async {
    final anterior = _lastEstado;
    if (anterior == estado) return;
    _lastEstado = estado;

    // Arrancó el viaje: el objetivo pasa de la recogida al destino, así que
    // hay que recalcular la ruta sí o sí. Sin esto `_routeCalculatedOnce`
    // bloqueaba el recálculo y la ruta seguía apuntando al punto de recogida
    // durante todo el trayecto. Se espera (no `unawaited`): el llamante
    // necesita la ruta nueva lista antes de procesar el siguiente ping de
    // ubicación del conductor.
    if (estado == SolicitudEstado.enRuta && anterior != null) {
      _routeCalculatedOnce = false;
      _lastTo = null;
      _initialRouteDistance = 0;
      await _updateRouteIfNeeded(forceRefresh: true);
    }

    if (estado == SolicitudEstado.enEspera) {
      _openWaitingModal();
      return;
    }
    _closeWaitingModal();
  }

  void _openWaitingModal() {
    if (waitingModalVisible) return;
    waitingModalVisible = true;
    waitingRemainingSeconds.value = 180;

    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (waitingRemainingSeconds.value <= 0) {
        timer.cancel();
        return;
      }
      waitingRemainingSeconds.value -= 1;
    });
    _safeNotify();
  }

  void _closeWaitingModal() {
    if (!waitingModalVisible && _waitingTimer == null) return;
    waitingModalVisible = false;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    _safeNotify();
  }

  void _checkProximityNotification(LatLng conductorPos) {
    if (_proximityNotified) return;
    final cliente = clienteLatLng;
    if (cliente == null) return;
    final distancia = _mathService.haversineMeters(conductorPos, cliente);
    if (distancia <= 70) {
      _proximityNotified = true;
      NotificacionesServicio.instance.showNotification(
        id: 77701,
        title: 'Tu conductor está cerca',
        body: 'El conductor esta por llegar. ¡Prepárate para abordar!',
      );
    }
  }

  void _handleConductorLocationUpdate(ViajeEntity item) {
    final next = item.conductor.ubicacion;
    if (next == null) return;

    _checkProximityNotification(next);

    final desvio = _movementEngine.distanceToRoute(next);
    final now = DateTime.now();
    final cooldownOk =
        _lastRouteRecalcAt == null ||
        now.difference(_lastRouteRecalcAt!).inSeconds >= 8;
    if (desvio != null && desvio > 40 && cooldownOk) {
      _lastRouteRecalcAt = now;
      unawaited(_updateRouteIfNeeded(forceRefresh: true));
    }

    _movementEngine.enqueueTarget(next);
  }

  Future<void> _updateRouteIfNeeded({bool forceRefresh = false}) async {
    if (!hasBothLocations || isUpdatingRoute) return;
    if (_routeCalculatedOnce && !forceRefresh) return;

    final from = conductorLatLngCrudo!;
    final to = objetivoActual!;

    final shouldRefresh =
        _lastFrom == null ||
        _lastTo == null ||
        _mathService.haversineMeters(_lastFrom!, from) > 20 ||
        _mathService.haversineMeters(_lastTo!, to) > 20;

    if (!forceRefresh && !shouldRefresh) return;

    isUpdatingRoute = true;
    _safeNotify();

    try {
      final points = await _ruta.obtenerRuta(origen: from, destino: to);

      // Una "ruta" de menos de dos puntos no es una ruta: no hay polilínea que
      // dibujar y `distanciaRuta` devuelve 0, así que la tarjeta mostraría
      // distancia y ETA en cero. Peor: al marcar `_routeCalculatedOnce` y
      // guardar `_lastFrom`/`_lastTo`, ese resultado degenerado quedaba fijado
      // y no se reintentaba hasta que el conductor se moviera más de 20 m.
      // Visto en dispositivo real: `Google Directions fetched: 1 points`.
      //
      // Se sale sin tocar el estado para que el próximo tick de GPS reintente.
      // (El caché local ya aplicaba esta misma validación al restaurar.)
      if (points.length < 2) {
        developer.log(
          'Ruta descartada: ${points.length} punto(s), se reintentará',
          name: 'ViajeClienteViewModel',
        );
        return;
      }

      final distance = _ruta.distanciaRuta(points);

      _movementEngine.setFullRoute(_mathService.densifyPolyline(points));
      final current = _movementEngine.currentPosition ?? from;
      _movementEngine.publishRemainingRoute(current, force: true);
      final remaining = _ruta.distanciaRuta(routePointsNotifier.value);

      distanceMeters = remaining > 0 ? remaining : distance;
      _initialRouteDistance = distance;
      eta = _ruta.etaDesdeDistancia(distanceMeters!);

      unawaited(
        _localCache.saveRoute(
          solicitudId: viajeId,
          points: points,
          distanceMeters: distance,
          etaSeconds: eta?.inSeconds,
        ),
      );

      _lastFrom = from;
      _lastTo = to;
      _routeCalculatedOnce = true;
      rutaVersion++;
    } catch (e, st) {
      developer.log(
        'Fallo al actualizar ruta: $e',
        name: 'ViajeClienteViewModel',
        level: 1000,
      );
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'ViajeClienteViewModel: fallo _updateRouteIfNeeded',
      );
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  Future<void> confirmarVoyEnCamino() async {
    if (isConfirmingVoyEnCamino) return;
    isConfirmingVoyEnCamino = true;
    _safeNotify();
    try {
      await _confirmarVoyEnCamino(viajeId);
      _closeWaitingModal();
    } finally {
      isConfirmingVoyEnCamino = false;
      _safeNotify();
    }
  }

  Future<void> cancelarViaje() async {
    if (isCancelling) return;
    isCancelling = true;
    _safeNotify();
    try {
      await _cancelarViaje(viajeId: viajeId, canceladoPor: 'cliente');
    } finally {
      isCancelling = false;
      _safeNotify();
    }
  }

  bool get debeSalir {
    final estado = viaje?.estado;
    return estado == SolicitudEstado.cancelado ||
        estado == SolicitudEstado.completado ||
        estado == SolicitudEstado.sinRespuesta;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _viajeSub?.cancel();
    _waitingTimer?.cancel();
    waitingRemainingSeconds.dispose();
    chat.dispose();
    _movementEngine.onTick = null;
    _movementEngine.onSnap = null;
    _movementEngine.dispose();
    // Limpiar las notificaciones del viaje (conductor cerca, mensajes de chat,
    // cambios de estado): sin esto quedaban acumuladas en la bandeja después de
    // que el viaje ya había terminado.
    unawaited(NotificacionesServicio.instance.cancelAll());
    super.dispose();
  }
}
