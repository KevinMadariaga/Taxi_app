import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/cancelar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/confirmar_voy_en_camino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/viewmodels/viaje_cliente_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/widgets/trip_info_card/trip_info_card.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/repositorios/viaje_repository_impl.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/trip_card_metrics.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/vistas/chat_screen.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/datos/repositorios/codigo_verificacion_repository_impl.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/theme/ride_button_styles.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/route_cache_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/panic_button_fab.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/trip_details_sheet.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/waiting_driver_modal.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

/// LA pantalla del cliente: reemplaza `TripTrackingScreen`
/// (`asignado`→`en camino`) y `RutaClienteDestinoView`
/// (`en ruta`→`completado`), un solo mapa/tracking continuo para todo el
/// viaje.
class ViajeClienteScreen extends StatefulWidget {
  const ViajeClienteScreen({
    super.key,
    required this.viajeId,
    required this.currentUserId,
  });

  final String viajeId;
  final String currentUserId;

  @override
  State<ViajeClienteScreen> createState() => _ViajeClienteScreenState();
}

class _ViajeClienteScreenState extends State<ViajeClienteScreen>
    with WidgetsBindingObserver {
  late final ViajeClienteViewModel _vm;
  GoogleMapController? _mapController;
  bool _initialCameraApplied = false;

  /// Margen alrededor del par cliente↔conductor al encuadrar la cámara. Cuanto
  /// más chico, más cerca queda el zoom de los marcadores y de la ruta.
  static const double _boundsPaddingCamara = 45;

  /// Zoom cuando solo se conoce uno de los dos puntos.
  static const double _zoomUnicoMarcador = 17;

  /// Dueña del stream del código, que la tarjeta solo pinta. Ya no hace
  /// falta un ajuste de alto por el banner: la tarjeta mide su contenido, así
  /// que al aparecer el código crece sola y el mapa cede ese alto.
  final _codigoRepository = CodigoVerificacionRepositoryImpl();
  StreamSubscription<CodigoVerificacionEntity?>? _codigoSub;
  CodigoVerificacionEntity? _codigo;

  bool _waitingSheetVisible = false;
  bool _hasNavigatedAway = false;

  /// Ruta de la modal de espera — para poder cerrarla sin arriesgar un pop
  /// sobre la pantalla del viaje (ver [_cerrarWaitingSheet]).
  ModalRoute<void>? _waitingSheetRoute;

  BitmapDescriptor? _conductorIcon;
  BitmapDescriptor? _conductorIconMirrored;
  bool _isMirroredHeading = false;

  /// Heading mostrado, suavizado hacia el objetivo con `MapHelper.lerpAngle`
  /// en vez de saltar al valor crudo del notifier en cada tick (50ms).
  double _displayedHeadingDeg = 0;
  bool _headingInicializado = false;

  // Reencuadre de cámara al cambiar de tramo (recogida → destino): ver
  // `_detectarCambioDeTramoParaCamara`.
  String? _lastEstadoCamara;
  bool _refitPendienteTramoDestino = false;
  int? _rutaVersionAlEntrarTramo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final viajeRepository = ViajeRepositoryImpl();

    _vm = ViajeClienteViewModel(
      viajeId: widget.viajeId,
      clienteId: widget.currentUserId,
      watchViaje: WatchViajeUseCase(viajeRepository),
      confirmarVoyEnCamino: ConfirmarVoyEnCaminoUseCase(
        ActualizarEstadoViajeUseCase(viajeRepository),
      ),
      cancelarViaje: CancelarViajeUseCase(viajeRepository),
      rutaDatasource: RutaDatasource(),
    );
    _vm.addListener(_onVmChanged);
    _vm.init();

    SessionHelper.setActiveSolicitudScreen('viaje_cliente');
    // Con esta pantalla montada, sus listeners avisan en tiempo real: el
    // handler de FCM en primer plano se hace a un lado para no duplicar.
    FcmService.instance.registrarPantallaDeViaje(widget.viajeId);
    _codigoSub = _codigoRepository.watchCodigo(widget.viajeId).listen((codigo) {
      if (!mounted) return;
      // Cambia el reparto de alto tarjeta/mapa, así que necesita rebuild.
      setState(() => _codigo = codigo);
    });
    _loadConductorMarkerIcon();
  }

  /// Ícono real del vehículo (carro/moto) en vez del marker por defecto —
  /// mismo asset y lógica de espejado que `trip_tracking_screen.dart`
  /// (`_loadTaxiMarkerIcon`/`_markerIconAndRotation`): el glyph no es
  /// simétrico arriba-abajo, así que para rumbos hacia el sur se usa el
  /// bitmap espejado en vez de rotarlo más allá de 90°/270°.
  Future<void> _loadConductorMarkerIcon() async {
    final assetPath = _vm.isMoto
        ? 'assets/img/icono_moto.png'
        : 'assets/img/icono_carro.png';
    try {
      final icon = await MarkerIconHelper.fromAsset(
        assetPath,
        size: const Size(40, 40),
      );
      final iconMirrored = await MarkerIconHelper.fromAsset(
        assetPath,
        size: const Size(40, 40),
        mirrored: true,
      );
      if (!mounted) return;
      setState(() {
        _conductorIcon = icon;
        _conductorIconMirrored = iconMirrored;
      });
    } catch (_) {
      // Cae al marker por defecto si el asset falla en cargar.
    }
  }

  (BitmapDescriptor?, double) _markerIconAndRotation(double heading) {
    // Suaviza el ángulo mostrado hacia el objetivo crudo del notifier —
    // sin esto la rotación saltaba al valor exacto de cada tick de 50ms.
    if (!_headingInicializado) {
      _displayedHeadingDeg = heading;
      _headingInicializado = true;
    } else {
      _displayedHeadingDeg = MapHelper.lerpAngle(_displayedHeadingDeg, heading, 0.25);
    }

    // La histéresis de espejado opera sobre el heading OBJETIVO (crudo), no
    // sobre el interpolado: si operara sobre el interpolado, el ícono
    // parpadearía dentro de la banda mientras el valor mostrado todavía
    // está cruzándola.
    if (_isMirroredHeading) {
      if (heading <= 80 || heading >= 280) _isMirroredHeading = false;
    } else {
      if (heading > 100 && heading < 260) _isMirroredHeading = true;
    }

    final icon = _isMirroredHeading
        ? (_conductorIconMirrored ?? _conductorIcon)
        : _conductorIcon;
    final rotation = _isMirroredHeading
        ? _displayedHeadingDeg - 180
        : _displayedHeadingDeg;
    return (icon, rotation);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FcmService.instance.limpiarPantallaDeViaje(widget.viajeId);
    _codigoSub?.cancel();
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _vm.pauseMovimientoConductor();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _vm.resumeMovimientoConductor();
    }
  }

  bool _iconoTipoVehiculoResuelto = false;

  void _onVmChanged() {
    // `isMoto` no se conoce hasta el primer snapshot del viaje — recargar
    // el ícono una vez que ya sabemos si es carro o moto (en `initState`
    // todavía era el default `false`).
    if (!_iconoTipoVehiculoResuelto && _vm.viaje != null) {
      _iconoTipoVehiculoResuelto = true;
      _loadConductorMarkerIcon();
    }
    _persistOrClearSession();
    _handleWaitingModal();
    _handleSalida();
    _fitCamera();
    _detectarCambioDeTramoParaCamara();
  }

  /// Reencuadra la cámara cuando el viaje pasa de recogida a destino
  /// (`objetivoActual` cambia de cliente a destino), pero solo una vez que
  /// la RUTA NUEVA ya está calculada (`rutaVersion` avanzó desde el momento
  /// del cambio de estado) — hacerlo en el instante del cambio de estado
  /// encuadraba la polilínea vieja, todavía apuntando a la recogida.
  void _detectarCambioDeTramoParaCamara() {
    final estado = _vm.viaje?.estado;
    if (estado != null && estado != _lastEstadoCamara) {
      final anterior = _lastEstadoCamara;
      _lastEstadoCamara = estado;
      if (estado == SolicitudEstado.enRuta && anterior != null) {
        _refitPendienteTramoDestino = true;
        _rutaVersionAlEntrarTramo = _vm.rutaVersion;
      }
    }
    if (_refitPendienteTramoDestino &&
        _vm.rutaVersion != _rutaVersionAlEntrarTramo) {
      _refitPendienteTramoDestino = false;
      _fitCamera(force: true);
    }
  }

  void _persistOrClearSession() {
    final estado = _vm.viaje?.estado;
    if (estado == null) return;

    if (SolicitudEstado.isSesionActiva(estado)) {
      RouteCacheService.saveForSolicitud(
        RouteCacheData(
          solicitudId: widget.viajeId,
          role: 'cliente',
          conductorName: _vm.conductorNombre,
          conductorPhotoUrl: _vm.conductorFotoUrl,
          conductorPlate: _vm.placaVehiculo,
          conductorVehiclePhotoUrl: _vm.vehiculoFotoUrl,
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
            _waitingSheetRoute = ModalRoute.of(sheetContext);
            return AnimatedBuilder(
              animation: _vm,
              builder: (context, _) {
                return WaitingDriverModal(
                  remainingSeconds: _vm.waitingRemainingSeconds,
                  isUpdating: _vm.isConfirmingVoyEnCamino,
                  onVoyEnCamino: () async {
                    await _vm.confirmarVoyEnCamino();
                    _cerrarWaitingSheet();
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
  /// Antes había dos caminos que la cerraban —el `pop()` del propio botón
  /// "Voy en camino" y el `maybePop()` de acá— y los dos se disparaban con el
  /// mismo cambio de estado: `confirmarVoyEnCamino()` cierra la modal en el
  /// viewmodel, eso notifica, y el listener popeaba el sheet ANTES de que
  /// volviera el `await` del botón. El segundo pop ya no encontraba el sheet y
  /// se llevaba puesta la pantalla del viaje: el cliente terminaba de vuelta
  /// en el detalle de la solicitud. Comparando contra la ruta guardada, el
  /// pop sobrante no hace nada.
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
          nextBuilder: (_) => ResumenClienteView(solicitudId: widget.viajeId),
          title: 'Viaje finalizado',
          subtitle: 'Preparando el resumen de tu viaje...',
          icon: Icons.flag_rounded,
          accentColor: AppColores.success,
          clearStackOnNext: true,
        );
        return;
      }

      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const HomeClienteView(),
        title: 'Solicitud cancelada',
        subtitle: estado == SolicitudEstado.sinRespuesta
            ? 'El conductor no recibió confirmación a tiempo.'
            : 'El servicio fue cancelado.',
        icon: Icons.close_rounded,
        accentColor: AppColores.error,
        drawCheck: false,
        clearStackOnNext: true,
      );
    });
  }

  /// Encuadra la cámara al objetivo vigente (`force: false`: solo la
  /// primera vez, guardado por `_initialCameraApplied`; `force: true`:
  /// reencuadre explícito, p. ej. al cambiar de tramo).
  ///
  /// Los bounds se calculan sobre conductor + `objetivoActual` + la
  /// polilínea restante — no solo cliente↔conductor como antes — para que
  /// en el tramo al destino entre la traza completa, no un segmento
  /// arbitrario.
  void _fitCamera({bool force = false}) {
    final map = _mapController;
    if ((_initialCameraApplied && !force) || map == null) return;
    final conductor = _vm.conductorLatLngCrudo;
    final objetivo = _vm.objetivoActual;
    final rutaPts = _vm.routePointsNotifier.value;
    final puntos = <LatLng>[
      if (conductor != null) conductor,
      if (objetivo != null) objetivo,
      ...rutaPts,
    ];
    if (puntos.isEmpty) return;

    _initialCameraApplied = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _animarCamaraAPuntos(map, puntos),
    );
  }

  Future<void> _animarCamaraAPuntos(
    GoogleMapController map,
    List<LatLng> puntos,
  ) async {
    if (!mounted || !identical(_mapController, map)) return;

    if (puntos.length < 2) {
      await _intentarAnimarCamara(
        map,
        CameraUpdate.newLatLngZoom(puntos.first, _zoomUnicoMarcador),
      );
      return;
    }

    var minLat = puntos.first.latitude;
    var maxLat = puntos.first.latitude;
    var minLng = puntos.first.longitude;
    var maxLng = puntos.first.longitude;
    for (final p in puntos) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    // Padding chico (antes 90): deja los marcadores más cerca del borde y
    // por lo tanto el zoom más pegado a la ruta.
    final update = CameraUpdate.newLatLngBounds(bounds, _boundsPaddingCamara);

    if (await _intentarAnimarCamara(map, update)) return;

    // `newLatLngBounds` puede fallar si el mapa todavía no tiene su tamaño
    // final layouteado (justo tras `onMapCreated`) — un reintento tras el
    // siguiente frame alcanza. Mismo patrón que `mapa_ruta_card.dart`.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || !identical(_mapController, map)) return;
    if (await _intentarAnimarCamara(map, update)) return;

    // Puntos casi idénticos u otro fallo persistente: Google Maps no puede
    // calcular bounds útiles — cae al zoom fijo sobre el primer punto.
    await _intentarAnimarCamara(
      map,
      CameraUpdate.newLatLngZoom(puntos.first, _zoomUnicoMarcador),
    );
  }

  Future<bool> _intentarAnimarCamara(
    GoogleMapController map,
    CameraUpdate update,
  ) async {
    try {
      await map.animateCamera(update);
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'viaje_cliente_screen: fitCamera');
      return false;
    }
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: widget.viajeId,
          currentUserId: widget.currentUserId,
          otherPartyLabel: 'conductor',
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
        tituloPersona: 'Conductor',
        nombrePersona: _vm.conductorNombre,
        fotoPersona: _vm.conductorFotoUrl,
        calificacion: _vm.viaje?.conductor.calificacion ?? 0,
        totalCalificaciones: _vm.viaje?.conductor.totalCalificaciones ?? 0,
        fotoVehiculo: _vm.vehiculoFotoUrl,
        placa: _vm.placaVehiculo,
        direccionRecoger: _vm.viaje?.cliente.direccion ?? '',
        direccionDestino: _vm.viaje?.destino.direccion ?? '',
        valorServicio: _vm.viaje?.valorServicio ?? 0,
        metodoPago: _vm.viaje?.metodoPago ?? '',
      ),
    );
  }

  /// Mismas 4 opciones que el `_MenuAyudaSheet` legacy de
  /// `trip_tracking_screen.dart` (estado de la solicitud, método de pago,
  /// problemas con el conductor, cancelar) — reutiliza las mismas rutas
  /// nombradas (`AppRoutes.ayuda*`), más "Ver detalles" que no estaba en el
  /// menú original pero es una entrada rápida útil acá.
  void _openAyuda() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColores.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColores.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.help_outline,
                color: AppColores.textPrimary,
              ),
              title: const Text('¿Cuál es el estado de mi solicitud?'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(
                  AppRoutes.ayudaEstadoSolicitud,
                  arguments: {'solicitudId': widget.viajeId},
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.payments_outlined,
                color: AppColores.textPrimary,
              ),
              title: const Text('Revisar o modificar mi pago'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(
                  AppRoutes.ayudaMetodoPago,
                  arguments: {
                    'solicitudId': widget.viajeId,
                    'metodoActual': _vm.viaje?.metodoPago ?? '',
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.report_problem_outlined,
                color: AppColores.textPrimary,
              ),
              title: const Text('Problemas con el conductor'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(
                  AppRoutes.ayudaProblemasConductor,
                  arguments: {
                    'solicitudId': widget.viajeId,
                    'nombreConductor': _vm.conductorNombre,
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppColores.textPrimary,
              ),
              title: const Text('Ver detalles del viaje'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openDetails();
              },
            ),
            // Una vez recogido (`en ruta`) el viaje ya no se puede cancelar
            // desde acá — por diseño del negocio, con el pasajero a bordo.
            if (_vm.viaje?.estado != SolicitudEstado.enRuta) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.close_rounded, color: AppColores.error),
                title: const Text(
                  'Cancelar viaje',
                  style: TextStyle(color: AppColores.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _onCancelar();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onCancelar() async {
    // Cinturón y tirantes: la regla de negocio vive acá, no solo en la
    // visibilidad del tile de Ayuda — cualquier otro camino que llegue a
    // `onCancel` (p. ej. `TripInfoCard.onCancel`) queda cubierto igual.
    if (_vm.viaje?.estado == SolicitudEstado.enRuta) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Cancelar solicitud?'),
        content: const Text('Se cancelará el viaje con este conductor.'),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: RideSecondaryButton(
                  text: 'No',
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColores.danger,
                      foregroundColor: AppColores.textWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Sí, cancelar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await _vm.cancelarViaje();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColores.background,
        body: AnimatedBuilder(
          animation: Listenable.merge([
            _vm.conductorPositionNotifier,
            _vm.conductorHeadingNotifier,
            _vm.routePointsNotifier,
          ]),
          builder: (context, _) {
            final conductorPos = _vm.conductorPositionNotifier.value;
            final routePts = _vm.routePointsNotifier.value;
            final fallback = const LatLng(8.2595534, -73.353469);
            final (conductorIcon, conductorRotation) = _markerIconAndRotation(
              _vm.conductorHeadingNotifier.value,
            );

            final markers = <Marker>{
              if (conductorPos != null)
                Marker(
                  markerId: const MarkerId('conductor'),
                  position: conductorPos,
                  rotation: conductorRotation,
                  flat: true,
                  anchor: const Offset(0.5, 0.5),
                  icon:
                      conductorIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        _vm.isMoto
                            ? BitmapDescriptor.hueGreen
                            : BitmapDescriptor.hueAzure,
                      ),
                ),
              // Pin del objetivo actual: el punto de recogida mientras el
              // conductor viene, y el destino una vez arrancó el viaje. Sin
              // él la polilínea terminaba en la nada y el pasajero no tenía
              // referencia de hacia dónde va.
              if (_vm.objetivoActual != null)
                Marker(
                  markerId: const MarkerId('objetivo'),
                  position: _vm.objetivoActual!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: _vm.viaje?.estado == SolicitudEstado.enRuta
                        ? 'Tu destino'
                        : 'Punto de recogida',
                  ),
                ),
            };

            final polylines = <Polyline>{
              if (routePts.length >= 2)
                Polyline(
                  polylineId: const PolylineId('viaje_cliente_route'),
                  points: routePts,
                  color: AppColores.buttonPrimary,
                  width: 5,
                ),
            };

            final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
            // La tarjeta ya no ocupa un % fijo de la pantalla: mide lo que
            // mide su contenido y el mapa se queda con el resto. Con el
            // reparto por flex anterior (45 %) sobraba aire en pantallas
            // altas y faltaba en las bajas, porque el contenido son píxeles
            // fijos. `TripCardMetrics` escala gaps y gráficos por franja de
            // alto, y `alturaMaximaFactor` es solo un techo para que en un
            // teléfono muy bajo la tarjeta no se coma el mapa (ahí sí
            // aparece scroll dentro de la tarjeta). El banner del código PIN
            // deja de necesitar ajuste: al aparecer, el alto crece solo.
            final metrics = TripCardMetrics.of(context);
            final alturaMaximaCard =
                MediaQuery.sizeOf(context).height * metrics.alturaMaximaFactor;

            return SafeArea(
              // `bottom: false`: el inset físico de abajo (home indicator
              // iOS / gesture bar Android) se maneja DENTRO del mapa (como
              // `padding` de `GoogleMap` + offset del FAB), no reservando
              // una franja en blanco fuera del `Stack` — con `SafeArea`
              // envolviendo toda la columna, esa franja quedaba en blanco
              // debajo del mapa en vez de ser parte visual de él.
              bottom: false,
              child: Column(
                children: [
                  // Arriba: info + chat + acciones, con el alto natural de su
                  // contenido. El `SingleChildScrollView` dentro del
                  // `ConstrainedBox` se encoge al contenido y solo scrollea
                  // si este supera `alturaMaximaCard`.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: alturaMaximaCard),
                    child: SingleChildScrollView(
                      child: TripInfoCard(
                        vm: _vm,
                        onChat: _openChat,
                        onDetails: _openDetails,
                        onHelp: _openAyuda,
                        onCancel: _onCancelar,
                        codigoVerificacion: _codigo,
                      ),
                    ),
                  ),
                  // Abajo: el mapa toma todo el espacio restante.
                  Expanded(
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target:
                                _vm.clienteLatLng ?? conductorPos ?? fallback,
                            zoom: 14,
                          ),
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: true,
                          padding: EdgeInsets.only(bottom: viewPaddingBottom),
                          markers: markers,
                          polylines: polylines,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            _fitCamera();
                          },
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
