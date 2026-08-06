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
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/info_map_split.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/vistas/chat_screen.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/theme/ride_button_styles.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/route_cache_service.dart';
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

class _ViajeClienteScreenState extends State<ViajeClienteScreen> {
  late final ViajeClienteViewModel _vm;
  GoogleMapController? _mapController;
  bool _initialCameraApplied = false;
  bool _waitingSheetVisible = false;
  bool _hasNavigatedAway = false;

  BitmapDescriptor? _conductorIcon;
  BitmapDescriptor? _conductorIconMirrored;
  bool _isMirroredHeading = false;

  @override
  void initState() {
    super.initState();

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
    if (_isMirroredHeading) {
      if (heading <= 80 || heading >= 280) _isMirroredHeading = false;
    } else {
      if (heading > 100 && heading < 260) _isMirroredHeading = true;
    }

    final icon = _isMirroredHeading
        ? (_conductorIconMirrored ?? _conductorIcon)
        : _conductorIcon;
    final rotation = _isMirroredHeading ? heading - 180 : heading;
    return (icon, rotation);
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
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
    _fitInitialCameraIfNeeded();
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
            return AnimatedBuilder(
              animation: _vm,
              builder: (context, _) {
                return WaitingDriverModal(
                  remainingSeconds: _vm.waitingRemainingSeconds,
                  isUpdating: _vm.isConfirmingVoyEnCamino,
                  onVoyEnCamino: () async {
                    await _vm.confirmarVoyEnCamino();
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
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

  void _fitInitialCameraIfNeeded() {
    final map = _mapController;
    if (_initialCameraApplied || map == null) return;
    final cliente = _vm.clienteLatLng;
    final conductor = _vm.conductorLatLngCrudo;
    final target = cliente ?? conductor;
    if (target == null) return;

    _initialCameraApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Con ambos puntos: encuadra el segmento cliente↔conductor entero
      // (zoom real según la distancia entre ellos) en vez de un zoom fijo
      // que se queda lejos si están cerca o corta al conductor si están
      // lejos. Con uno solo: fallback a zoom fijo, cercano al marcador.
      if (cliente != null && conductor != null) {
        final bounds = LatLngBounds(
          southwest: LatLng(
            math.min(cliente.latitude, conductor.latitude),
            math.min(cliente.longitude, conductor.longitude),
          ),
          northeast: LatLng(
            math.max(cliente.latitude, conductor.latitude),
            math.max(cliente.longitude, conductor.longitude),
          ),
        );
        try {
          await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
          return;
        } catch (_) {
          // Puntos casi idénticos: Google Maps no puede calcular bounds
          // útiles — cae al zoom fijo de abajo.
        }
      }
      await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    });
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: widget.viajeId,
          currentUserId: widget.currentUserId,
          otherPartyLabel: 'conductor',
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
        ),
      ),
    );
  }

  Future<void> _onCancelar() async {
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
            final (infoFlex, mapFlex) = InfoMapSplit.of(context);

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
                  // Mitad superior: info + chat + acciones. `LayoutBuilder` +
                  // `ConstrainedBox(minHeight:)` hace que la tarjeta ocupe
                  // TODA la mitad disponible (como ya hace el mapa) en vez de
                  // encogerse al alto de su contenido.
                  Expanded(
                    flex: infoFlex,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: TripInfoCard(
                              vm: _vm,
                              onChat: _openChat,
                              onDetails: _openDetails,
                              onHelp: _openAyuda,
                              onCancel: _onCancelar,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Mitad inferior: mapa.
                  Expanded(
                    flex: mapFlex,
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target:
                                _vm.clienteLatLng ?? conductorPos ?? fallback,
                            zoom: 14,
                          ),
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          compassEnabled: true,
                          padding: EdgeInsets.only(bottom: viewPaddingBottom),
                          markers: markers,
                          polylines: polylines,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            _fitInitialCameraIfNeeded();
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
