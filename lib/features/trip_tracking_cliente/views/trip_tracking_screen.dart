import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/features/trip_tracking_cliente/viewmodels/trip_route_tracking_viewmodel.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_route_tracking_screen.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteDestinoView.dart';

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
  bool _assignmentNotificationShown = false;
  static final Set<String> _globalAssignmentNotificationsShown = <String>{};
  String? _lastEstadoProcesado;
  String? _lastPersistedStatus;

  @override
  void initState() {
    super.initState();
    _estadoController = SolicitudEstadoController();
    _loadTaxiMarkerIcon();
    _showDriverAssignedNotification();
    // Persist current screen so reload restores this exact view
    try {
      SessionHelper.setActiveSolicitudScreen('trip_tracking');
    } catch (_) {}
  }

  Future<void> _showDriverAssignedNotification() async {
    if (_assignmentNotificationShown) return;

    final sid = widget.solicitudId;
    if (sid.isNotEmpty && _globalAssignmentNotificationsShown.contains(sid)) {
      _assignmentNotificationShown = true;
      return;
    }

    _assignmentNotificationShown = true;
    if (sid.isNotEmpty) _globalAssignmentNotificationsShown.add(sid);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await NotificationService.instance.init();
        await NotificationService.instance.showNotification(
          DateTime.now().millisecondsSinceEpoch % 100000,
          'Se asigno conductor',
          'Ya viene a recogerte.',
        );
      } catch (_) {
        // No interrumpe la experiencia si la notificacion falla.
      }
    });
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
                rotation: vm.conductorHeading,
                anchor: const Offset(0.5, 0.5),
              ),
          };

          final polylines = <Polyline>{
            if (vm.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('ruta_real_time'),
                points: vm.routePoints,
                color: AppColores.buttonPrimary,
                width: 5,
              ),
          };

          final initialTarget =
              vm.clienteLatLng ??
              vm.conductorLatLng ??
              const LatLng(8.2595534, -73.353469);

          final width = MediaQuery.of(context).size.width;
          final isTablet = width >= 900;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: Scaffold(
              body: Builder(builder: (ctx) {
                final mq = MediaQuery.of(ctx);
                final screenH = mq.size.height;
                final safeBottom = mq.padding.bottom;
                final mapH = (screenH * 0.70).clamp(200.0, screenH - 120.0);
                final panelH = screenH - mapH;

                return Stack(
                  children: [
                    Column(
                      children: [
                        // Map area (70%)
                        SizedBox(
                          height: mapH,
                          width: double.infinity,
                          child: Stack(
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
                                top: mq.padding.top + 14,
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
                                  top: mq.padding.top + 74,
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
                                bottom: 16,
                                child: FloatingActionButton(
                                  heroTag: 'focus_trip_tracking',
                                  backgroundColor: AppColores.buttonPrimary,
                                  onPressed: () => _toggleFocus(vm),
                                  child: Icon(
                                    vm.focusMode == MapFocusMode.clientOnly
                                        ? Icons.person_pin_circle
                                        : Icons.fit_screen,
                                    color: AppColores.textWhite,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom panel (30%)
                        SizedBox(
                          height: panelH,
                          width: double.infinity,
                          child: Container(
                            color: AppColores.cardBackground,
                            child: SafeArea(
                              top: false,
                              child: Center(
                                child: SizedBox(
                                  height: (panelH - safeBottom).clamp(120.0, double.infinity),
                                  width: isTablet ? 700 : (width - 32).clamp(260.0, double.infinity),
                                  child: UserTripInfoCard(
                                    name: vm.nombreUsuarioCard,
                                    vehiclePlate: vm.placaVehiculo,
                                    userPhotoUrl: vm.fotoUsuario,
                                    vehiclePhotoUrl: vm.fotoVehiculo,
                                    unreadCount: vm.unreadCount,
                                    isCancelling: vm.isCancelling,
                                    onOpenChat: () => _openChat(vm),
                                    onCancel: () => _onCancelPressed(vm),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                );
              }),
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
    // Avoid triggering navigation on initial load when status is 'asignado'.
    // This prevents reload from immediately replacing this screen.
    if (_lastEstadoProcesado == null && normalizado == 'asignado') {
      _lastEstadoProcesado = normalizado;
      return;
    }

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
      final icon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(30, 50)),
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
    return SolicitudEstado.isSesionActiva(status);
  }

  bool _shouldClearSolicitud(String status) {
    return SolicitudEstado.isTerminal(status);
  }

  Future<void> _goToRutaClienteDestino() async {
    if (_rutaDestinoNavigationDone || !mounted) return;
    _rutaDestinoNavigationDone = true;
    // Mark the intended screen so reloads will open RutaClienteDestino
    try {
      await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino');
    } catch (_) {}

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RutaClienteDestino(
          idSolicitud: widget.solicitudId,
          // passing the actual solicitudId from this screen
          // currentUserId: widget.currentUserId,
          // tipoUsuario: TipoUsuarioTracking.cliente,
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

    // After attempting cancel, verify remote state and delete the solicitud
    // from Firestore if it is actually cancelled.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final estadoRaw = (data?['status'] ?? data?['estado'] ?? '')
            .toString();
        final estadoNorm = SolicitudEstadoController.normalizeEstado(estadoRaw);
        if (estadoNorm == SolicitudEstado.cancelado ||
            estadoNorm == SolicitudEstado.sinRespuesta) {
          try {
            await FirebaseFirestore.instance
                .collection('solicitudes')
                .doc(widget.solicitudId)
                .delete();
          } catch (_) {}

          try {
            await SessionHelper.clearActiveSolicitud();
          } catch (_) {}
          try {
            await RouteCacheService.clearSolicitud(widget.solicitudId);
          } catch (_) {}
        }
      }
    } catch (_) {}

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
    if (estadoNormalizado != SolicitudEstado.cancelado &&
        estadoNormalizado != SolicitudEstado.sinRespuesta) {
      return;
    }

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
        try { await SessionHelper.clearActiveSolicitudScreen(); } catch (_) {}
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
    _mapController?.dispose();
    _estadoController.dispose();
    super.dispose();
  }
}
