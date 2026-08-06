import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/datos/repositorios/codigo_verificacion_repository_impl.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/repositorios/viaje_repository_impl.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/info_map_split.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/vistas/chat_screen.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/driver_ubicacion_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/navegacion_externa_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/cancelar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/finalizar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/iniciar_ruta_destino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/reportar_llegada_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/viewmodels/viaje_conductor_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/arrival_confirmation_sheet.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/driver_trip_card.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/widgets/codigo_verificacion_sheet.dart';
import 'package:taxi_app/core/app_colores.dart';
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
      cancelarViaje: CancelarViajeUseCase(viajeRepository),
      ubicacionDatasource: DriverUbicacionDatasource(),
      rutaDatasource: RutaDatasource(),
      navegacionDatasource: NavegacionExternaDatasource(),
    );
    _vm.addListener(_onVmChanged);
    _vm.init();

    SessionHelper.setActiveSolicitudScreen('viaje_conductor');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
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
    _handleSalida();
  }

  void _persistOrClearSession() {
    final estado = _vm.viaje?.estado;
    if (estado == null) return;

    if (SolicitudEstado.isSesionActiva(estado)) {
      RouteCacheService.saveForSolicitud(
        RouteCacheData(
          solicitudId: widget.viajeId,
          role: 'conductor',
          clientName: _vm.clienteNombre,
          clientAddress: _vm.clienteDireccion,
          clientLat: _vm.viaje?.cliente.ubicacion?.latitude,
          clientLng: _vm.viaje?.cliente.ubicacion?.longitude,
          conductorId: _vm.conductorId,
        ),
      );
    } else if (SolicitudEstado.isTerminal(estado)) {
      SessionHelper.clearActiveSolicitud();
      SessionHelper.clearActiveSolicitudScreen();
      RouteCacheService.clearSolicitud(widget.viajeId);
    }
  }

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
            return AnimatedBuilder(
              animation: _vm,
              builder: (context, _) {
                return DriverWaitingClientModal(
                  remainingSeconds: _vm.waitingRemainingSeconds,
                  canStartTrip: _vm.waitingCanStartTrip,
                  isLoading: _vm.isValidatingCodigo,
                  onStartTrip: () {
                    Navigator.of(sheetContext).pop();
                    _abrirCodigoVerificacion();
                  },
                );
              },
            );
          },
        ).whenComplete(() => _waitingSheetVisible = false);
      });
      return;
    }

    if (!_vm.waitingModalVisible && _waitingSheetVisible) {
      _waitingSheetVisible = false;
      if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    }
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
    await CodigoVerificacionSheet.mostrar(
      context,
      onValidar: (codigo) => _vm.validarCodigoRecogida(codigo),
      isValidating: () => _vm.isValidatingCodigo,
    );
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

  Future<void> _onCancelarViaje() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar el viaje?'),
        content: const Text(
          'El cliente será notificado y la solicitud quedará cancelada. '
          'Úsalo solo si no puedes completar la recogida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColores.error),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _vm.cancelarViaje();
    // No se navega acá: al pasar a `cancelado`, `_handleSalida` (que ya
    // escucha los estados terminales) se encarga de sacar de la pantalla.
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: widget.viajeId,
          currentUserId: _vm.conductorId,
          otherPartyLabel: 'cliente',
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
            final (infoFlex, mapFlex) = InfoMapSplit.of(
              context,
              baseInfoFlex: 45,
            );

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
                  // Mitad superior: info + chat + acciones. `LayoutBuilder` +
                  // `ConstrainedBox(minHeight:)` hace que la tarjeta ocupe
                  // TODA la mitad disponible (como ya hace el mapa) en vez de
                  // encogerse al alto de su contenido y dejar un hueco vacío
                  // debajo si el contenido es más corto que la mitad — solo
                  // scrollea si el contenido es más alto que eso.
                  Expanded(
                    flex: infoFlex,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: DriverTripCard(
                              vm: _vm,
                              onChat: _openChat,
                              onDetails: _openDetails,
                              onReportarLlegada: _onReportarLlegada,
                              onComenzarRuta: _abrirCodigoVerificacion,
                              onTerminarViaje: _onTerminarViaje,
                              onCancelar: _onCancelarViaje,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Mitad inferior: mapa estático (Google Static Maps),
                  // mismo widget que usa la preview del conductor antes de
                  // aceptar — deja de depender de un `GoogleMapController`
                  // en vivo acá.
                  Expanded(
                    flex: mapFlex,
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
