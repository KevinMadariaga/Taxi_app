import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/datos/repositorios/codigo_verificacion_repository_impl.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/repositorios/viaje_repository_impl.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/trip_card_metrics.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/vistas/chat_screen.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/driver_ubicacion_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/navegacion_externa_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/finalizar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/iniciar_ruta_destino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/reportar_llegada_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/viewmodels/viaje_conductor_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/arrival_confirmation_sheet.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/driver_trip_card.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/widgets/codigo_verificacion_sheet.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/route_cache_service.dart';
import 'package:taxi_app/features/driver_trip/widgets/driver_waiting_client_modal.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/panic_button_fab.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/trip_details_sheet.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/widgets/preview_solicitud/widgets/mapa_previsualizacion_solicitud.dart';

/// LA pantalla del conductor: reemplaza `DriverTripScreen` (fase de
/// recogida) y `RutaDestinoView`/`RutaDestinoViewModel` (fase de destino),
/// cubriendo `asignado → completado` en una sola clase, un solo mapa, un
/// solo tracking GPS.
class ViajeConductorScreen extends StatefulWidget {
  const ViajeConductorScreen({super.key, required this.viajeId});

  final String viajeId;

  @override
  State<ViajeConductorScreen> createState() => _ViajeConductorScreenState();
}

class _ViajeConductorScreenState extends State<ViajeConductorScreen>
    with WidgetsBindingObserver {
  late final ViajeConductorViewModel _vm;
  bool _waitingSheetVisible = false;
  bool _hasNavigatedAway = false;

  /// Última sesión persistida y último error ya mostrado — evitan repetir la
  /// escritura a disco y el SnackBar en cada `notifyListeners`.
  String? _ultimaHuellaSesion;
  String? _ultimoErrorMostrado;

  /// Ruta de la modal de espera — para cerrarla sin arriesgar un pop sobre la
  /// pantalla del viaje (ver [_cerrarWaitingSheet]).
  ModalRoute<void>? _waitingSheetRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final conductorId = ViajeConductorViewModel.currentUid() ?? '';
    final viajeRepository = ViajeRepositoryImpl();
    final codigoRepository = CodigoVerificacionRepositoryImpl();

    _vm = ViajeConductorViewModel(
      viajeId: widget.viajeId,
      conductorId: conductorId,
      watchViaje: WatchViajeUseCase(viajeRepository),
      actualizarEstado: ActualizarEstadoViajeUseCase(viajeRepository),
      reportarLlegada: ReportarLlegadaUseCase(
        actualizarEstado: ActualizarEstadoViajeUseCase(viajeRepository),
        generarCodigo: GenerarCodigoVerificacionUseCase(codigoRepository),
      ),
      iniciarRutaDestino: IniciarRutaDestinoUseCase(
        actualizarEstado: ActualizarEstadoViajeUseCase(viajeRepository),
        validarCodigo: ValidarCodigoVerificacionUseCase(codigoRepository),
      ),
      finalizarViaje: FinalizarViajeUseCase(
        ActualizarEstadoViajeUseCase(viajeRepository),
      ),
      ubicacionDatasource: DriverUbicacionDatasource(),
      rutaDatasource: RutaDatasource(),
      navegacionDatasource: NavegacionExternaDatasource(),
    );
    _vm.addListener(_onVmChanged);
    final initFuture = _vm.init();

    // QA sin taps: dispara la simulación de recorrido sola al montar,
    // relanzando con `--dart-define=SIMULAR_RECORRIDO_QA=full` (recorrido
    // completo) o `=last` (salta directo al último punto, sin retomar GPS
    // real después) — necesario en dispositivos donde no se pueden inyectar
    // taps sintéticos. Se encadena DESPUÉS de que `init()` termine su propio
    // fetch inicial de GPS real (`_ubicacion.iniciarEnvio`, awaited adentro
    // de `init()`) — si se disparaba en paralelo, ese fetch tardío podía
    // pisar el punto simulado (visto en pruebas: la posición real llegaba
    // ~3s después y sobrescribía el punto que se acababa de mandar).
    if (kDebugMode) {
      const modoQA = String.fromEnvironment('SIMULAR_RECORRIDO_QA');
      if (modoQA == 'full') {
        unawaited(initFuture.then((_) => _vm.simularRecorridoDePrueba()));
      } else if (modoQA == 'last') {
        unawaited(
          initFuture.then((_) => _vm.reposicionarEnUltimaUbicacionSimulada()),
        );
      } else if (modoQA == 'cliente') {
        unawaited(initFuture.then((_) => _vm.irAUbicacionDelCliente()));
      }
    }

    SessionHelper.setActiveSolicitudScreen('viaje_conductor');
    // Con esta pantalla montada, sus listeners avisan en tiempo real: el
    // handler de FCM en primer plano se hace a un lado para no duplicar.
    FcmService.instance.registrarPantallaDeViaje(widget.viajeId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FcmService.instance.limpiarPantallaDeViaje(widget.viajeId);
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Solo `paused` cuenta como "la app se fue al fondo".
    //
    // Antes también entraban `inactive` y `hidden`, y eso arrancaba el servicio
    // de ubicación en segundo plano —con su notificación persistente— por
    // eventos que no son salir de la app: en iOS `inactive` lo dispara bajar el
    // Centro de Control, una llamada entrante o cualquier alerta del sistema, y
    // `hidden` es solo el paso previo a `paused`. El usuario veía aparecer la
    // notificación del servicio sin haber salido, y cada `inactive → resumed`
    // cruzaba el arranque del isolate (450 ms de espera) con su parada, dejando
    // el stream en primer plano y el servicio en background escribiendo GPS a
    // la vez.
    if (state == AppLifecycleState.paused) {
      _vm.onAppPausedOrInactive();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _vm.onAppResumed();
    }
  }

  void _onVmChanged() {
    _persistOrClearSession();
    _handleWaitingModal();
    _mostrarError();
    _handleSalida();
  }

  /// El VM escribe `errorText` en 5 rutas de fallo y hasta acá no lo leía
  /// nadie: si "Ya llegué al punto" o "Terminar viaje" fallaban, el botón
  /// volvía a su estado normal sin ningún mensaje y el conductor no tenía
  /// forma de saber que la escritura no ocurrió.
  void _mostrarError() {
    final error = _vm.errorText;
    if (error == null || error == _ultimoErrorMostrado) return;
    _ultimoErrorMostrado = error;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColores.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      _vm.limpiarError();
      _ultimoErrorMostrado = null;
    });
  }

  void _persistOrClearSession() {
    final estado = _vm.viaje?.estado;
    if (estado == null) return;

    if (SolicitudEstado.isSesionActiva(estado)) {
      final datos = RouteCacheData(
        solicitudId: widget.viajeId,
        role: 'conductor',
        clientName: _vm.clienteNombre,
        clientAddress: _vm.clienteDireccion,
        clientLat: _vm.viaje?.cliente.ubicacion?.latitude,
        clientLng: _vm.viaje?.cliente.ubicacion?.longitude,
        conductorId: _vm.conductorId,
      );

      // Dirty-check: esto corre en CADA `notifyListeners`, y durante la espera
      // hay uno por segundo — eran ~360 escrituras a `SharedPreferences` por
      // espera, todas con los mismos datos.
      final huella = _huellaSesion(datos);
      if (huella == _ultimaHuellaSesion) return;
      _ultimaHuellaSesion = huella;

      RouteCacheService.saveForSolicitud(datos);
    } else if (SolicitudEstado.isTerminal(estado)) {
      SessionHelper.clearActiveSolicitud();
      SessionHelper.clearActiveSolicitudScreen();
      RouteCacheService.clearSolicitud(widget.viajeId);
      _ultimaHuellaSesion = null;
    }
  }

  String _huellaSesion(RouteCacheData d) => [
    d.solicitudId,
    d.clientName,
    d.clientAddress,
    d.clientLat,
    d.clientLng,
    d.conductorId,
  ].join('|');

  void _handleWaitingModal() {
    if (_vm.waitingModalVisible && !_waitingSheetVisible) {
      _waitingSheetVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) {
            _waitingSheetRoute = ModalRoute.of(sheetContext);
            return AnimatedBuilder(
              animation: _vm,
              builder: (context, _) {
                return DriverWaitingClientModal(
                  remainingSeconds: _vm.waitingRemainingSeconds,
                  canStartTrip: _vm.waitingCanStartTrip,
                  isLoading: _vm.isValidatingCodigo,
                  onStartTrip: () {
                    // El orden importa: primero el VM deja de pedir la modal
                    // de espera (si no, el próximo `notifyListeners` — hay uno
                    // por cada punto GPS — la reabre encima del PIN, y es
                    // `isDismissible: false`), y recién después se cierra.
                    _vm.abrirIngresoCodigo();
                    _cerrarWaitingSheet();
                    _abrirCodigoVerificacion();
                  },
                );
              },
            );
          },
        ).whenComplete(() {
          _waitingSheetVisible = false;
          _waitingSheetRoute = null;
        });
      });
      return;
    }

    if (!_vm.waitingModalVisible && _waitingSheetVisible) {
      _cerrarWaitingSheet();
    }
  }

  /// Cierra la modal de espera SOLO si su ruta sigue arriba.
  ///
  /// El `maybePop()` que había acá no miraba QUÉ ruta estaba encima: cuando
  /// dos caminos pedían cerrar la modal con el mismo cambio de estado (el
  /// botón de la modal y este listener), el segundo pop ya no encontraba el
  /// sheet y se llevaba puesta la pantalla del viaje. Comparando contra la
  /// ruta guardada, el pop sobrante no hace nada.
  void _cerrarWaitingSheet() {
    final route = _waitingSheetRoute;
    _waitingSheetVisible = false;
    _waitingSheetRoute = null;
    if (!mounted || route == null || !route.isCurrent) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _handleSalida() {
    if (!_vm.debeSalir || _hasNavigatedAway) return;
    _hasNavigatedAway = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final estado = _vm.viaje?.estado;
      if (estado == SolicitudEstado.completado) {
        await navigateWithIntermediateLoader(
          context: context,
          nextBuilder: (_) => ResumenConductorView(solicitudId: widget.viajeId),
          title: 'Viaje finalizado',
          subtitle: 'Preparando el resumen del viaje...',
          icon: Icons.flag_rounded,
          accentColor: AppColores.success,
          clearStackOnNext: true,
        );
        return;
      }

      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const InicioConductor(),
        title: 'Solicitud cancelada',
        subtitle: _vm.mensajeSalida ?? 'El servicio fue cancelado.',
        icon: Icons.close_rounded,
        accentColor: AppColores.error,
        drawCheck: false,
        clearStackOnNext: true,
      );
    });
  }

  Future<void> _abrirCodigoVerificacion() async {
    _vm.abrirIngresoCodigo();
    bool? validado;
    try {
      validado = await CodigoVerificacionSheet.mostrar(
        context,
        onValidar: (codigo) => _vm.validarCodigoRecogida(codigo),
      );
    } finally {
      // Si el conductor descartó el sheet sin validar, el VM devuelve la modal
      // de espera: sin eso quedaba sin ningún camino para reintentar.
      _vm.cerrarIngresoCodigo();
    }
    // Solo con PIN correcto: cubre el frame en que el VM recalcula la ruta
    // hacia el destino (`_handleEstadoTransition`) y hace visible el cambio
    // de tramo, en vez de que la card se reconstruya en seco.
    if (validado == true && mounted) {
      await showIntermediateTransitionOverlay(
        context: context,
        title: 'Ruta iniciada',
        subtitle: 'Llevando al pasajero a su destino...',
        icon: Icons.route_rounded,
      );
    }
  }

  Future<void> _onReportarLlegada() async {
    final confirmado = await ArrivalConfirmationSheet.mostrar(context);
    if (confirmado == true) {
      await _vm.reportarLlegada();
    }
  }

  Future<void> _onTerminarViaje() async {
    await _vm.finalizarViaje();
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: widget.viajeId,
          currentUserId: _vm.conductorId,
          otherPartyLabel: 'cliente',
          // El controller del VM ya está bindeado a este viaje; crear otro
          // duplicaba el listener y la notificación de cada mensaje.
          controller: _vm.chat,
        ),
      ),
    );
  }

  void _openDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColores.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TripDetailsSheet(
        tituloPersona: 'Cliente',
        nombrePersona: _vm.clienteNombre,
        fotoPersona: _vm.clientePhotoUrl,
        calificacion: 0,
        totalCalificaciones: 0,
        fotoVehiculo: '',
        placa: '',
        direccionRecoger: _vm.clienteDireccion,
        direccionDestino: _vm.destinoDireccion,
        valorServicio: _vm.valorServicio,
        metodoPago: _vm.metodoPago,
        mostrarVehiculo: false,
        mostrarCalificacion: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColores.background,
        body: AnimatedBuilder(
          animation: _vm,
          builder: (context, _) {
            final driver = _vm.driverLatLng;
            final objetivo = _vm.objetivoActual;

            final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
            // La card ya no ocupa un % fijo de la pantalla (`InfoMapSplit`):
            // mide lo que mide su contenido y el mapa se queda con el resto,
            // mismo modelo que ya usa `ViajeClienteScreen`. Con
            // `ConstrainedBox(minHeight:)` anterior la card se estiraba a la
            // mitad de la pantalla aunque su contenido fuera más corto,
            // dejando un hueco vacío debajo de "Terminar viaje".
            final metrics = TripCardMetrics.of(context);
            final alturaMaximaCard =
                MediaQuery.sizeOf(context).height * metrics.alturaMaximaFactor;

            return SafeArea(
              // `bottom: false`: el inset físico de abajo (home indicator
              // iOS / gesture o barra de Android) se maneja DENTRO del
              // mapa (el FAB de SOS se desplaza ese offset), no reservando
              // una franja en blanco fuera del `Stack` — con `SafeArea`
              // envolviendo toda la columna, esa franja quedaba en blanco
              // debajo del mapa en vez de ser parte visual de él.
              bottom: false,
              child: Column(
                children: [
                  // Arriba: info + chat + acciones, alta al contenido con un
                  // techo (`alturaMaximaFactor`) para que en un teléfono muy
                  // bajo no se coma el mapa — ahí sí aparece scroll.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: alturaMaximaCard),
                    child: SingleChildScrollView(
                      child: DriverTripCard(
                        vm: _vm,
                        onChat: _openChat,
                        onDetails: _openDetails,
                        onReportarLlegada: _onReportarLlegada,
                        onComenzarRuta: _abrirCodigoVerificacion,
                        onTerminarViaje: _onTerminarViaje,
                      ),
                    ),
                  ),
                  // Resto: mapa estático (Google Static Maps), mismo widget
                  // que usa la preview del conductor antes de aceptar — deja
                  // de depender de un `GoogleMapController` en vivo acá.
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: objetivo != null
                              ? MapaPrevisualizacionSolicitud(
                                  driverLocation: driver,
                                  clientLocation: objetivo,
                                  isMoto: _vm.isMoto,
                                  routePoints: _vm.routePoints,
                                  heading: _vm.routePoints.length >= 2
                                      ? _vm.driverHeading
                                      : null,
                                  // Vista al rumbo: el conductor abajo y su
                                  // objetivo arriba, para que la traza se lea
                                  // como "voy hacia allá" y no norte-arriba.
                                  orientarHaciaCliente: true,
                                )
                              : Container(color: AppColores.grey300),
                        ),
                        if (_vm.isLoading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.6),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          bottom: 16 + viewPaddingBottom,
                          child: const PanicButtonFab(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
