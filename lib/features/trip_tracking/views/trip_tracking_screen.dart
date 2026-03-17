import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking/viewmodels/trip_route_tracking_viewmodel.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/features/trip_tracking/views/trip_route_tracking_screen.dart';
import 'package:taxi_app/services/route_cache_service.dart';

import '../controllers/solicitud_estado_controller.dart';
import '../viewmodels/trip_tracking_viewmodel.dart';
import '../widgets/trip_status_overlay.dart';
import '../widgets/user_trip_info_card.dart';
import 'trip_chat_screen.dart';

class TripTrackingScreen extends StatefulWidget {
  const TripTrackingScreen({
    super.key,
    required this.solicitudId,
    required this.currentUserId,
    this.cancelledBy = 'cliente',
    this.onSolicitudCancelada,
  });

  final String solicitudId;
  final String currentUserId;
  final String cancelledBy;
  final VoidCallback? onSolicitudCancelada;

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  GoogleMapController? _mapController;
  late final SolicitudEstadoController _estadoController;
  BitmapDescriptor? _taxiMarkerIcon;
  bool _initialCameraApplied = false;
  bool _cancelledNavigationDone = false;
  bool _rutaDestinoNavigationDone = false;
  String? _lastEstadoProcesado;
  String? _lastPersistedStatus;

  @override
  void initState() {
    super.initState();
    _estadoController = SolicitudEstadoController();
    _loadTaxiMarkerIcon();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TripTrackingViewModel>(
      create: (_) => TripTrackingViewModel(
        solicitudId: widget.solicitudId,
        currentUserId: widget.currentUserId,
        cancelledBy: widget.cancelledBy,
      )..init(),
      child: Consumer<TripTrackingViewModel>(
        builder: (context, vm, _) {
          _syncSolicitudPersistence(vm);
          _handleTripStateIfNeeded(vm);
          _handleSolicitudCanceladaIfNeeded(vm);
          _fitInitialCameraIfNeeded(vm);

          final markers = <Marker>{
            if (vm.clienteLatLng != null)
              Marker(
                markerId: const MarkerId('cliente'),
                position: vm.clienteLatLng!,
                infoWindow: const InfoWindow(title: 'Cliente'),
              ),
            if (vm.conductorLatLng != null)
              Marker(
                markerId: const MarkerId('conductor'),
                position: vm.conductorLatLng!,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon:
                    _taxiMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
              ),
          };

          final polylines = <Polyline>{
            if (vm.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('ruta_real_time'),
                points: vm.routePoints,
                color: AppColores.buttonChat,
                width: 5,
              ),
          };

          final initialTarget =
              vm.clienteLatLng ??
              vm.conductorLatLng ??
              const LatLng(8.2595534, -73.353469);

          final width = MediaQuery.of(context).size.width;
          final isTablet = width >= 900;

          return Scaffold(
            body: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialTarget,
                    zoom: 14,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  markers: markers,
                  polylines: polylines,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _fitInitialCameraIfNeeded(vm);
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TripStatusOverlay(
                      distanceText: vm.distanciaTexto,
                      etaText: vm.etaTexto,
                      isOffline: vm.isOffline,
                    ),
                  ),
                ),
                if (vm.isOffline ||
                    vm.errorText?.toLowerCase().contains('cache') == true)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 74,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColores.warning,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColores.overlayLight,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            color: AppColores.textWhite,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sin conexion. Mostrando datos guardados.',
                              style: TextStyle(
                                color: AppColores.textWhite,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: isTablet ? 280 : 220,
                  child: FloatingActionButton(
                    heroTag: 'focus_trip_tracking',
                    backgroundColor: AppColores.buttonPrimary,
                    onPressed: () => _toggleFocus(vm),
                    child: Icon(
                      vm.focusMode == MapFocusMode.clientOnly
                          ? Icons.person_pin_circle
                          : Icons.fit_screen,
                      color: AppColores.textPrimary,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: UserTripInfoCard(
                      name: vm.nombreUsuarioCard,
                      userPhotoUrl: vm.fotoUsuario,
                      vehiclePhotoUrl: vm.fotoVehiculo,
                      unreadCount: vm.unreadCount,
                      isCancelling: vm.isCancelling,
                      onOpenChat: () => _openChat(vm),
                      onCancel: () => _onCancelPressed(vm),
                    ),
                  ),
                ),
                if (vm.isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: AppColores.overlayLight,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColores.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleTripStateIfNeeded(TripTrackingViewModel vm) {
    final estado = vm.solicitud?.estado;
    if (estado == null || estado.isEmpty) return;

    final normalizado = SolicitudEstadoController.normalizeEstado(estado);
    if (_lastEstadoProcesado == normalizado) return;
    _lastEstadoProcesado = normalizado;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _estadoController.handleEstadoCambio(
        context: context,
        solicitudId: widget.solicitudId,
        estadoRaw: estado,
        onIrRutaClienteDestino: _goToRutaClienteDestino,
      );
    });
  }

  Future<void> _loadTaxiMarkerIcon() async {
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(50, 50)),
        'assets/img/taxi_icon.png',
      );

      if (!mounted) return;
      setState(() {
        _taxiMarkerIcon = icon;
      });
    } catch (_) {}
  }

  void _syncSolicitudPersistence(TripTrackingViewModel vm) {
    final estado = vm.solicitud?.estado;
    if (estado == null || estado.trim().isEmpty) return;

    final normalizado = SolicitudEstadoController.normalizeEstado(estado);
    if (_lastPersistedStatus == normalizado) return;
    _lastPersistedStatus = normalizado;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_shouldPersistSolicitud(normalizado)) {
        try {
          await SessionHelper.setActiveSolicitud(widget.solicitudId);
          await RouteCacheService.saveForSolicitud(
            RouteCacheData(
              solicitudId: widget.solicitudId,
              role: 'cliente',
              clientName: vm.nombreUsuarioCard,
              clientLat: vm.clienteLatLng?.latitude,
              clientLng: vm.clienteLatLng?.longitude,
            ),
          );
        } catch (_) {}
        return;
      }

      if (_shouldClearSolicitud(normalizado)) {
        try {
          await SessionHelper.clearActiveSolicitud();
          await RouteCacheService.clearSolicitud(widget.solicitudId);
        } catch (_) {}
      }
    });
  }

  bool _shouldPersistSolicitud(String status) {
    return status == 'asignado' ||
        status == 'en_espera' ||
        status == 'en_camino' ||
        status == 'en_ruta';
  }

  bool _shouldClearSolicitud(String status) {
    return status == 'cancelado' ||
        status.contains('complet') ||
        status.contains('finaliz');
  }

  Future<void> _goToRutaClienteDestino() async {
    if (_rutaDestinoNavigationDone || !mounted) return;
    _rutaDestinoNavigationDone = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripRouteTrackingScreen(
          solicitudId: widget.solicitudId,
          currentUserId: widget.currentUserId,
          tipoUsuario: TipoUsuarioTracking.cliente,
        ),
      ),
    );
  }

  Future<void> _onCancelPressed(TripTrackingViewModel vm) async {
    if (_cancelledNavigationDone || vm.isCancelling) return;

    Object? cancelError;
    try {
      await vm.cancelSolicitud();
    } catch (error) {
      cancelError = error;
    }

    if (!mounted) return;
    _navigateToInicioCliente();

    if (cancelError != null) {
      debugPrint(
        '[TripTrackingScreen] Cancelacion remota pendiente por error: $cancelError',
      );
    }
  }

  Future<void> _openChat(TripTrackingViewModel vm) async {
    await vm.markChatAsRead();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const TripChatScreen(),
        ),
      ),
    );

    await vm.markChatAsRead();
  }

  Future<void> _toggleFocus(TripTrackingViewModel vm) async {
    final map = _mapController;
    if (map == null) return;

    if (vm.focusMode == MapFocusMode.clientOnly) {
      final target = vm.clienteLatLng;
      if (target != null) {
        await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      }
      await vm.toggleMapFocusMode();
      return;
    }

    final a = vm.clienteLatLng;
    final b = vm.conductorLatLng;
    if (a != null && b != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          a.latitude < b.latitude ? a.latitude : b.latitude,
          a.longitude < b.longitude ? a.longitude : b.longitude,
        ),
        northeast: LatLng(
          a.latitude > b.latitude ? a.latitude : b.latitude,
          a.longitude > b.longitude ? a.longitude : b.longitude,
        ),
      );
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    await vm.toggleMapFocusMode();
  }

  void _fitInitialCameraIfNeeded(TripTrackingViewModel vm) {
    final map = _mapController;
    if (_initialCameraApplied || map == null) return;

    final a = vm.clienteLatLng;
    final b = vm.conductorLatLng;
    if (a == null || b == null) return;

    _initialCameraApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bounds = LatLngBounds(
        southwest: LatLng(
          a.latitude < b.latitude ? a.latitude : b.latitude,
          a.longitude < b.longitude ? a.longitude : b.longitude,
        ),
        northeast: LatLng(
          a.latitude > b.latitude ? a.latitude : b.latitude,
          a.longitude > b.longitude ? a.longitude : b.longitude,
        ),
      );
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    });
  }

  void _handleSolicitudCanceladaIfNeeded(TripTrackingViewModel vm) {
    if (_cancelledNavigationDone) return;
    final estadoRaw = vm.solicitud?.estado;
    if (estadoRaw == null || estadoRaw.isEmpty) return;

    final estadoNormalizado = SolicitudEstadoController.normalizeEstado(
      estadoRaw,
    );
    if (estadoNormalizado != 'cancelado') return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateToInicioCliente();
    });
  }

  void _navigateToInicioCliente() {
    if (_cancelledNavigationDone || !mounted) return;
    _cancelledNavigationDone = true;

    if (widget.onSolicitudCancelada != null) {
      try {
        widget.onSolicitudCancelada!.call();
      } catch (_) {}

      // Si el callback externo no navega (o retorna sin hacer nada),
      // hacemos fallback local para garantizar salida de la pantalla.
      if (!mounted) return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await SessionHelper.clearActiveSolicitud();
        await RouteCacheService.clearSolicitud(widget.solicitudId);
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioClienteView()),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _estadoController.dispose();
    super.dispose();
  }
}
