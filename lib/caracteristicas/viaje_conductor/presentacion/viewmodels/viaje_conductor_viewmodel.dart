import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/controladores/chat_controller.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/driver_ubicacion_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/navegacion_externa_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/finalizar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/iniciar_ruta_destino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/reportar_llegada_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_route_math_service.dart';

/// Tramo del viaje en el que está el conductor — determina el objetivo del
/// mapa/ruta: recoger al cliente, o llevarlo al destino.
enum TramoViajeConductor { recogida, destino }

/// LA clase del conductor: reemplaza `DriverTripController` (fase de
/// recogida) y `RutaDestinoViewModel` (fase de destino), que vivían en dos
/// pantallas separadas con su propio tracking/ruteo/lifecycle cada una.
/// Único `ChangeNotifier` para todo el viaje, `asignado` → `completado`.
class ViajeConductorViewModel extends ChangeNotifier {
  ViajeConductorViewModel({
    required this.viajeId,
    required this.conductorId,
    required WatchViajeUseCase watchViaje,
    required ActualizarEstadoViajeUseCase actualizarEstado,
    required ReportarLlegadaUseCase reportarLlegada,
    required IniciarRutaDestinoUseCase iniciarRutaDestino,
    required FinalizarViajeUseCase finalizarViaje,
    required DriverUbicacionDatasource ubicacionDatasource,
    required RutaDatasource rutaDatasource,
    required NavegacionExternaDatasource navegacionDatasource,
    ChatController? chatController,
  }) : _watchViaje = watchViaje,
       _actualizarEstado = actualizarEstado,
       _reportarLlegada = reportarLlegada,
       _iniciarRutaDestino = iniciarRutaDestino,
       _finalizarViaje = finalizarViaje,
       _ubicacion = ubicacionDatasource,
       _ruta = rutaDatasource,
       _navegacion = navegacionDatasource,
       chat =
           chatController ??
           ChatController(
             viajeId: viajeId,
             currentUserId: conductorId,
             otherPartyLabel: 'cliente',
           );

  final String viajeId;
  final String conductorId;

  final WatchViajeUseCase _watchViaje;
  final ActualizarEstadoViajeUseCase _actualizarEstado;
  final ReportarLlegadaUseCase _reportarLlegada;
  final IniciarRutaDestinoUseCase _iniciarRutaDestino;
  final FinalizarViajeUseCase _finalizarViaje;
  final DriverUbicacionDatasource _ubicacion;
  final RutaDatasource _ruta;
  final NavegacionExternaDatasource _navegacion;
  final TripRouteMathService _mathService = const TripRouteMathService();

  final ChatController chat;

  ViajeEntity? viaje;
  bool isLoading = true;
  bool isRouteLoading = false;
  bool isSendingArrival = false;
  bool isValidatingCodigo = false;
  bool isFinalizandoViaje = false;
  bool hasReportedArrival = false;
  String? errorText;

  List<LatLng> routePoints = const [];
  double? distanceMeters;
  Duration? eta;
  double driverHeading = 0.0;

  /// Progreso real (0..1) del tramo vigente — recogida o destino, según
  /// [tramoActual]. Alimenta `BarraProgresoDireccional`.
  double progresoTramo = 0.0;

  /// Plazo que tiene el cliente para confirmar antes de marcar el viaje como
  /// `sin respuesta`.
  static const int _segundosEspera = 180;

  bool waitingModalVisible = false;
  bool waitingCanStartTrip = false;
  int waitingRemainingSeconds = _segundosEspera;

  /// `true` mientras el conductor tiene abierto el sheet del código PIN.
  ///
  /// Sin esto, la modal de espera se reabría ENCIMA del PIN: al tocar
  /// "Comenzar ruta" la pantalla cerraba el sheet pero [waitingModalVisible]
  /// seguía en `true`, así que el siguiente `notifyListeners` — y hay uno por
  /// cada punto GPS del propio conductor, porque el tracking escribe en la
  /// misma solicitud que este VM escucha — volvía a cumplir la condición de
  /// apertura. La modal es `isDismissible: false`, o sea que tapaba el PIN sin
  /// forma de cerrarla y el viaje no podía arrancar.
  bool codigoSheetVisible = false;

  /// `true` cuando el viaje llegó a un estado terminal (cancelado,
  /// completado, sin respuesta) — la pantalla debe salir.
  bool debeSalir = false;
  String? mensajeSalida;

  bool isAppInBackground = false;

  StreamSubscription<ViajeEntity>? _viajeSub;
  Timer? _waitingTimer;
  String? _lastEstado;
  LatLng? _lastFrom;
  LatLng? _lastTo;
  double? _distanciaInicialTramo;
  bool _disposed = false;
  bool _timeoutActualizandoEstado = false;
  bool _notificacionesListas = false;
  bool _errorEsDeCarga = false;

  TramoViajeConductor get tramoActual {
    final estado = viaje?.estado;
    return estado == SolicitudEstado.enRuta
        ? TramoViajeConductor.destino
        : TramoViajeConductor.recogida;
  }

  LatLng? get driverLatLng => viaje?.conductor.ubicacion;

  LatLng? get objetivoActual {
    final v = viaje;
    if (v == null) return null;
    return tramoActual == TramoViajeConductor.destino
        ? v.destino.ubicacion
        : v.cliente.ubicacion;
  }

  bool get hasBothLocations => driverLatLng != null && objetivoActual != null;

  String get distanceText =>
      distanceMeters == null ? '--' : _ruta.formatearDistancia(distanceMeters!);
  String get etaText => eta == null ? '--' : _ruta.formatearEta(eta!);

  String get clienteNombre {
    final n = viaje?.cliente.nombre ?? '';
    return n.isNotEmpty ? n : 'Cliente';
  }

  String get clienteDireccion => viaje?.cliente.direccion ?? '';
  String get clientePhotoUrl => viaje?.cliente.fotoUrl ?? '';
  String get destinoDireccion => viaje?.destino.direccion ?? '';
  double get valorServicio => viaje?.valorServicio ?? 0;
  String get metodoPago => viaje?.metodoPago ?? '';
  bool get isMoto => viaje?.isMoto ?? false;

  Future<void> init() async {
    await _ensureNotifications();
    _bindViaje();
    chat.onChanged = () => _safeNotify();
    chat.bind();

    try {
      await _ubicacion.iniciarEnvio(conductorId: conductorId, viajeId: viajeId);
    } catch (e) {
      errorText = 'No se pudo iniciar tracking GPS: $e';
      _safeNotify();
    }
  }

  void _bindViaje() {
    _viajeSub?.cancel();
    _viajeSub = _watchViaje(viajeId).listen(
      (incoming) async {
        viaje = incoming;
        isLoading = false;
        // Solo se limpia el error DE CARGA. Antes se borraba `errorText`
        // entero en cada snapshot, y como el tracking GPS del conductor
        // escribe en esta misma solicitud, llega un snapshot cada pocos
        // segundos: un error de "no se pudo terminar el viaje" se borraba
        // antes de que la pantalla alcanzara a mostrarlo.
        if (_errorEsDeCarga) {
          errorText = null;
          _errorEsDeCarga = false;
        }
        _safeNotify();

        _handleEstadoTransition(incoming.estado);
        await _refreshRouteIfNeeded();
      },
      onError: (error) {
        isLoading = false;
        errorText = 'No se pudo cargar el viaje: $error';
        _errorEsDeCarga = true;
        _safeNotify();
      },
    );
  }

  Future<void> reportarLlegada() async {
    if (isSendingArrival || hasReportedArrival) return;

    isSendingArrival = true;
    _safeNotify();
    try {
      await _reportarLlegada(viajeId);
      hasReportedArrival = true;
    } catch (e) {
      errorText = 'No se pudo reportar la llegada: $e';
    } finally {
      isSendingArrival = false;
      _safeNotify();
    }
  }

  /// Valida el código que el conductor ingresó — si es correcto, la
  /// transición enCamino→enRuta ocurre acá mismo (ver
  /// `IniciarRutaDestinoUseCase`). El widget que llama decide qué mostrar
  /// según el [ResultadoValidacionCodigo] devuelto.
  Future<ResultadoValidacionCodigo> validarCodigoRecogida(
    String codigoIngresado,
  ) async {
    // El sheet ya se protege en su botón, pero `onSubmitted` del teclado no
    // pasa por ahí: sin este guard, tocar "Listo" con una validación en vuelo
    // disparaba una segunda y escribía `validadoEn` y `en ruta` dos veces.
    if (isValidatingCodigo) return ResultadoValidacionCodigo.enProceso;

    isValidatingCodigo = true;
    _safeNotify();
    try {
      final resultado = await _iniciarRutaDestino(
        viajeId: viajeId,
        codigoIngresado: codigoIngresado,
      );
      if (resultado == ResultadoValidacionCodigo.correcto) {
        _closeWaitingModal();
      }
      return resultado;
    } finally {
      isValidatingCodigo = false;
      _safeNotify();
    }
  }

  /// Sin guard, cada tap repetía la escritura y pisaba `completedAt` y
  /// `'fecha de terminacion'` con una hora nueva; y sin `catch`, un fallo se
  /// perdía en el gap async del `onPressed` y el conductor tocaba "Terminar
  /// viaje" sin que pasara nada, para siempre.
  Future<void> finalizarViaje() async {
    if (isFinalizandoViaje || debeSalir) return;

    isFinalizandoViaje = true;
    errorText = null;
    _safeNotify();
    try {
      await _finalizarViaje(viajeId);
    } catch (e) {
      errorText = 'No se pudo terminar el viaje: $e';
    } finally {
      isFinalizandoViaje = false;
      _safeNotify();
    }
  }

  /// Borra el mensaje de error una vez que el conductor lo vio.
  void limpiarError() {
    if (errorText == null) return;
    errorText = null;
    _safeNotify();
  }

  // El conductor NO cancela el viaje: por diseño del negocio eso lo hace el
  // cliente, y este lado solo reacciona al estado `cancelado` que llega por el
  // stream (ver `_handleEstadoTransition`). Antes había un `cancelarViaje()`
  // con su botón en `DriverTripCard`; se retiró junto con la marca
  // `_canceladoPorMi`, que servía únicamente para distinguir el mensaje de
  // salida cuando el origen era este conductor.

  Future<void> abrirNavegacionExterna() async {
    final objetivo = objetivoActual;
    if (objetivo == null) return;
    await _navegacion.abrirRutaHacia(objetivo);
  }

  /// Llamar desde `didChangeAppLifecycleState` (paused/inactive/hidden):
  /// detiene el stream en vivo y arranca el servicio en background — nunca
  /// ambos corriendo a la vez.
  Future<void> onAppPausedOrInactive() async {
    isAppInBackground = true;
    await _ubicacion.detener();
    try {
      await initializeBackgroundService();
      await startBackgroundTrackingService();
      // Da un momento al isolate para registrar sus listeners antes de
      // enviarle el comando — mismo margen que ya usaba `driver_trip_screen.dart`.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      FlutterBackgroundService().invoke('startTracking', {
        'userId': conductorId,
        'userType': 'conductor',
        'solicitudId': viajeId,
      });
    } catch (e, st) {
      developer.log(
        'Error al iniciar tracking en segundo plano: $e',
        name: 'ViajeConductorViewModel',
      );
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'ViajeConductorViewModel: fallo al iniciar background tracking',
      );
    }
  }

  /// Llamar desde `didChangeAppLifecycleState` (resumed): detiene el
  /// servicio en background y retoma el stream en vivo.
  Future<void> onAppResumed() async {
    isAppInBackground = false;
    await stopBackgroundTrackingService();

    try {
      await _ubicacion.iniciarEnvio(conductorId: conductorId, viajeId: viajeId);
    } catch (e, st) {
      developer.log(
        'Error al retomar tracking en primer plano: $e',
        name: 'ViajeConductorViewModel',
      );
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'ViajeConductorViewModel: fallo al retomar tracking foreground',
      );
    }

    try {
      await _ubicacion.enviarUbicacionActual(
        conductorId: conductorId,
        viajeId: viajeId,
      );
    } catch (_) {
      // El stream recién reiniciado ya se encarga del próximo punto.
    }
  }

  void _handleEstadoTransition(String estado) {
    if (_lastEstado == estado) return;
    _lastEstado = estado;

    if (estado == SolicitudEstado.cancelado) {
      _closeWaitingModal();
      debeSalir = true;
      // Solo el cliente cancela, así que el origen no es ambiguo.
      mensajeSalida = 'El cliente canceló la solicitud.';
      unawaited(
        _notify('Servicio cancelado', 'El cliente ha cancelado el servicio.'),
      );
      _safeNotify();
      return;
    }

    if (estado == SolicitudEstado.sinRespuesta) {
      _closeWaitingModal();
      debeSalir = true;
      mensajeSalida =
          'El cliente no respondió a tiempo. La solicitud fue cancelada por sin respuesta.';
      if (isAppInBackground) {
        unawaited(
          NotificacionesServicio.instance.showTripNotification(
            title: '⚠️ Sin respuesta del cliente',
            body:
                'El cliente no contestó la validación, se cancelará el servicio.',
          ),
        );
      }
      _safeNotify();
      return;
    }

    if (estado == SolicitudEstado.completado) {
      _closeWaitingModal();
      debeSalir = true;
      mensajeSalida = null;
      _safeNotify();
      return;
    }

    if (estado == SolicitudEstado.enRuta) {
      _closeWaitingModal();
      // Cambia de tramo: fuerza recálculo de ruta contra el nuevo objetivo
      // (destino) en vez del cliente.
      _lastFrom = null;
      _lastTo = null;
      _distanciaInicialTramo = null;
      _safeNotify();
      return;
    }

    if (estado == SolicitudEstado.enEspera) {
      _openWaitingModal();
      waitingCanStartTrip = false;
      _safeNotify();
      return;
    }

    if (estado == SolicitudEstado.enCamino) {
      if (!waitingModalVisible) {
        _openWaitingModal();
      }
      waitingCanStartTrip = true;
      _stopWaitingTimer();
      unawaited(
        NotificacionesServicio.instance.showTripNotification(
          title: 'Cliente en camino',
          body: 'El cliente va en camino, espera que llegue al vehículo.',
        ),
      );
      _safeNotify();
      return;
    }

    _closeWaitingModal();
  }

  Future<void> _refreshRouteIfNeeded() async {
    if (!hasBothLocations || isRouteLoading) return;

    final from = driverLatLng!;
    final to = objetivoActual!;

    final shouldRefresh =
        _lastFrom == null ||
        _lastTo == null ||
        _mathService.haversineMeters(_lastFrom!, from) > 20 ||
        _mathService.haversineMeters(_lastTo!, to) > 20;

    if (!shouldRefresh) return;

    isRouteLoading = true;
    _safeNotify();

    try {
      final polyline = await _ruta.obtenerRuta(origen: from, destino: to);

      // Menos de dos puntos no es una ruta: sin polilínea, con distancia y ETA
      // en 0. Si además se guardan `_lastFrom`/`_lastTo`, ese resultado queda
      // fijado y no se reintenta hasta que el conductor se mueva más de 20 m.
      // Mismo caso visto del lado cliente (`fetched: 1 points`).
      if (polyline.length < 2) {
        developer.log(
          'Ruta descartada: ${polyline.length} punto(s), se reintentará',
          name: 'ViajeConductorViewModel',
        );
        return;
      }

      final dist = _ruta.distanciaRuta(polyline);

      routePoints = polyline;
      distanceMeters = dist;
      eta = _ruta.etaDesdeDistancia(dist);
      _distanciaInicialTramo ??= dist == 0 ? null : dist;
      progresoTramo = _calcularProgreso(dist);

      try {
        if (routePoints.length >= 2) {
          final nearest = _mathService.nearestPointIndex(from, routePoints);
          LatLng? target;
          if (nearest < routePoints.length - 1) {
            target = routePoints[nearest + 1];
          } else if (nearest > 0) {
            target = routePoints[nearest];
          }
          if (target != null) {
            driverHeading = _mathService.bearingBetween(from, target);
          }
        }
      } catch (_) {
        driverHeading = 0.0;
      }

      _lastFrom = from;
      _lastTo = to;
    } finally {
      isRouteLoading = false;
      _safeNotify();
    }
  }

  double _calcularProgreso(double distanciaRestante) {
    final inicial = _distanciaInicialTramo;
    if (inicial == null || inicial <= 0) return 0.0;
    final avance = (inicial - distanciaRestante) / inicial;
    return avance.clamp(0.0, 1.0);
  }

  /// El conductor abre el sheet del PIN: la modal de espera se retira y no
  /// puede volver sola mientras el PIN esté a la vista.
  void abrirIngresoCodigo() {
    codigoSheetVisible = true;
    waitingModalVisible = false;
    _stopWaitingTimer();
    _safeNotify();
  }

  /// El sheet del PIN se cerró. Si el código no llegó a validarse y el viaje
  /// sigue esperando al cliente, la modal de espera vuelve — sin ella el
  /// conductor se quedaba sin ningún camino para reintentar.
  void cerrarIngresoCodigo() {
    if (!codigoSheetVisible) return;
    codigoSheetVisible = false;

    final estado = viaje?.estado;
    if (estado == SolicitudEstado.enEspera ||
        estado == SolicitudEstado.enCamino) {
      _openWaitingModal(reiniciarCuenta: false);
      // `en camino` = el cliente ya confirmó: se puede arrancar sin esperar y
      // sin reanudar la cuenta regresiva.
      if (estado == SolicitudEstado.enCamino) {
        waitingCanStartTrip = true;
        _stopWaitingTimer();
      }
    }
    _safeNotify();
  }

  /// [reiniciarCuenta] `false` reabre la modal conservando el tiempo que
  /// quedaba: al volver del sheet del PIN, reiniciar los 180 s le regalaría al
  /// cliente un plazo nuevo cada vez que el conductor abre y cierra el PIN.
  void _openWaitingModal({bool reiniciarCuenta = true}) {
    if (waitingModalVisible || codigoSheetVisible) return;

    waitingModalVisible = true;
    waitingCanStartTrip = false;
    if (reiniciarCuenta) waitingRemainingSeconds = _segundosEspera;

    _stopWaitingTimer();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (waitingCanStartTrip) {
        _stopWaitingTimer();
        return;
      }
      if (waitingRemainingSeconds <= 0) {
        waitingRemainingSeconds = 0;
        _stopWaitingTimer();
        unawaited(_handleWaitingTimeoutNoResponse());
        _safeNotify();
        return;
      }
      waitingRemainingSeconds -= 1;
      _safeNotify();
    });

    _safeNotify();
  }

  void _closeWaitingModal() {
    if (!waitingModalVisible && _waitingTimer == null) return;
    waitingModalVisible = false;
    waitingCanStartTrip = false;
    _stopWaitingTimer();
    _safeNotify();
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
  }

  Future<void> _handleWaitingTimeoutNoResponse() async {
    if (_timeoutActualizandoEstado) return;
    final estadoActual = viaje?.estado;
    if (estadoActual == SolicitudEstado.enCamino ||
        estadoActual == SolicitudEstado.enRuta ||
        estadoActual == SolicitudEstado.cancelado ||
        estadoActual == SolicitudEstado.sinRespuesta) {
      return;
    }

    _timeoutActualizandoEstado = true;
    try {
      await _actualizarEstado(
        ActualizarEstadoViajeParams(
          viajeId: viajeId,
          estado: SolicitudEstado.sinRespuesta,
        ),
      );
    } catch (e) {
      errorText = 'No se pudo marcar sin respuesta: $e';
      _safeNotify();
    } finally {
      _timeoutActualizandoEstado = false;
    }
  }

  /// Las notificaciones son accesorias al viaje: si el plugin no arranca, el
  /// conductor igual tiene que poder ver el viaje y operarlo. Antes esto se
  /// llamaba sin proteger como PRIMERA línea de `init()`, así que un fallo
  /// acá cortaba el `init` entero y la pantalla se quedaba sin stream de
  /// Firestore, sin ruta y sin tracking.
  Future<void> _ensureNotifications() async {
    if (_notificacionesListas) return;
    try {
      await NotificacionesServicio.instance.init();
      _notificacionesListas = true;
    } catch (e, st) {
      // `ErrorReporter` en vez de `recordError` directo: éste es best-effort y
      // no debe romper si Crashlytics no está listo.
      ErrorReporter.report(
        e,
        st,
        reason: 'ViajeConductorViewModel: fallo al iniciar notificaciones',
      );
    }
  }

  Future<void> _notify(String title, String body) async {
    try {
      await _ensureNotifications();
      await NotificacionesServicio.instance.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
      );
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'ViajeConductorViewModel: fallo al mostrar notificación local ($title)',
      );
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  static String? currentUid() => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _disposed = true;
    _viajeSub?.cancel();
    _stopWaitingTimer();
    chat.dispose();
    unawaited(_ubicacion.detener());
    // Cortar TAMBIÉN el servicio en segundo plano. Antes solo se detenía al
    // terminar el viaje (`finalizarViajeConTracking`) y en el resumen: si la
    // pantalla se destruía por cualquier otra vía —cancelación del cliente,
    // `sin respuesta`, cierre de sesión— el foreground service seguía vivo
    // mandando GPS y escribiendo en Firestore, con su notificación en la
    // barra, hasta que el conductor volviera a abrir la app.
    unawaited(stopBackgroundTrackingService());
    // Y limpiar las notificaciones del viaje (llegada, chat, avisos de
    // estado): sin esto quedaban acumuladas en la bandeja después de que el
    // viaje ya había terminado.
    unawaited(NotificacionesServicio.instance.cancelAll());
    super.dispose();
  }
}
