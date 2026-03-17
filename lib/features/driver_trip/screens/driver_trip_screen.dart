import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking/viewmodels/trip_route_tracking_viewmodel.dart';
import 'package:taxi_app/features/trip_tracking/views/trip_route_tracking_screen.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';

import '../controllers/driver_trip_controller.dart';
import '../widgets/driver_client_info_card.dart';
import '../widgets/driver_top_status_card.dart';
import '../widgets/driver_waiting_client_modal.dart';
import 'driver_chat_screen.dart';

class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen>
    with WidgetsBindingObserver {
  late final DriverTripController _controller;
  GoogleMapController? _mapController;

  bool _initialCameraApplied = false;
  bool _navigating = false;
  bool _waitingSheetVisible = false;
  bool _waitingModalOperationQueued = false;
  BuildContext? _waitingModalContext;
  String? _lastPersistedStatus;
  bool _backgroundTrackingEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = DriverTripController(tripId: widget.tripId);
    _controller.init();
  }

  @override
  void dispose() {
    _stopBackgroundTrackingIfNeeded();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _startBackgroundTrackingIfNeeded();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _stopBackgroundTrackingIfNeeded();
      _controller.onAppResumed();
    }
  }

  Future<void> _startBackgroundTrackingIfNeeded() async {
    if (_backgroundTrackingEnabled) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      await startBackgroundTrackingService();
      final service = FlutterBackgroundService();
      service.invoke('startTracking', {
        'userId': uid,
        'userType': 'conductor',
        'solicitudId': widget.tripId,
      });
      _backgroundTrackingEnabled = true;
    } catch (_) {}
  }

  Future<void> _stopBackgroundTrackingIfNeeded() async {
    if (!_backgroundTrackingEnabled) return;
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
    } catch (_) {}
    _backgroundTrackingEnabled = false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DriverTripController>.value(
      value: _controller,
      child: Consumer<DriverTripController>(
        builder: (context, controller, _) {
          _syncSolicitudPersistence(controller);
          _handlePendingNavigation(controller);
          _handleWaitingModal(controller);
          _fitInitialCameraIfNeeded(controller);

          final markers = <Marker>{
            if (controller.clientLatLng != null)
              Marker(
                markerId: const MarkerId('client_marker'),
                position: controller.clientLatLng!,
                infoWindow: const InfoWindow(title: 'Cliente'),
              ),
            if (controller.driverLatLng != null)
              Marker(
                markerId: const MarkerId('driver_marker'),
                position: controller.driverLatLng!,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
          };

          final polylines = <Polyline>{
            if (controller.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('driver_trip_route'),
                points: controller.routePoints,
                color: AppColores.buttonChat,
                width: 5,
              ),
          };

          final fallback = const LatLng(8.2595534, -73.353469);
          final initialTarget =
              controller.clientLatLng ?? controller.driverLatLng ?? fallback;

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
                  onMapCreated: (map) {
                    _mapController = map;
                    _fitInitialCameraIfNeeded(controller);
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DriverTopStatusCard(
                      distanceText: controller.distanceText,
                      etaText: controller.etaText,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: isTablet ? 280 : 230,
                  child: FloatingActionButton(
                    heroTag: 'driver_map_focus_btn',
                    backgroundColor: AppColores.buttonPrimary,
                    onPressed: () => _toggleFocus(controller),
                    child: Icon(
                      controller.focusMode == DriverMapFocusMode.clientOnly
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
                    child: DriverClientInfoCard(
                      clientName: controller.clientName,
                      clientAddress: controller.clientAddress,
                      clientPhotoUrl: controller.clientPhotoUrl,
                      unreadCount: controller.unreadCount,
                      onOpenChat: () => _openChat(controller),
                      onOpenNavigation: () => _openNavigation(controller),
                      onReportArrival: controller.reportArrival,
                      isSendingArrival: controller.isSendingArrival,
                    ),
                  ),
                ),
                if (controller.isLoading)
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

  Future<void> _openChat(DriverTripController controller) async {
    await controller.markChatAsRead();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: controller,
          child: const DriverChatScreen(),
        ),
      ),
    );

    await controller.markChatAsRead();
  }

  Future<void> _openNavigation(DriverTripController controller) async {
    final client = controller.clientLatLng;
    if (client == null) return;

    final googleNav = Uri.parse(
      'google.navigation:q=${client.latitude},${client.longitude}&mode=d',
    );
    if (await canLaunchUrl(googleNav)) {
      await launchUrl(googleNav, mode: LaunchMode.externalApplication);
      return;
    }

    final webFallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${client.latitude},${client.longitude}&travelmode=driving',
    );
    await launchUrl(webFallback, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleFocus(DriverTripController controller) async {
    final map = _mapController;
    if (map == null) return;

    if (controller.focusMode == DriverMapFocusMode.clientOnly) {
      final target = controller.clientLatLng;
      if (target != null) {
        await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      }
      await controller.toggleMapFocusMode();
      return;
    }

    final a = controller.clientLatLng;
    final b = controller.driverLatLng;
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

    await controller.toggleMapFocusMode();
  }

  void _fitInitialCameraIfNeeded(DriverTripController controller) {
    final map = _mapController;
    if (_initialCameraApplied || map == null) return;

    final a = controller.clientLatLng;
    final b = controller.driverLatLng;
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
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
    });
  }

  void _syncSolicitudPersistence(DriverTripController controller) {
    final rawStatus = controller.trip?.status;
    if (rawStatus == null || rawStatus.trim().isEmpty) return;

    final status = DriverTripController.normalizeStatus(rawStatus);
    if (_lastPersistedStatus == status) return;
    _lastPersistedStatus = status;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_shouldPersistSolicitud(status)) {
        try {
          await SessionHelper.setActiveSolicitud(widget.tripId);
          await RouteCacheService.saveForSolicitud(
            RouteCacheData(
              solicitudId: widget.tripId,
              role: 'conductor',
              clientName: controller.clientName,
              clientAddress: controller.clientAddress,
              clientLat: controller.clientLatLng?.latitude,
              clientLng: controller.clientLatLng?.longitude,
              conductorId: FirebaseAuth.instance.currentUser?.uid,
            ),
          );
        } catch (_) {}
        return;
      }

      if (_shouldClearSolicitud(status)) {
        try {
          await SessionHelper.clearActiveSolicitud();
          await RouteCacheService.clearSolicitud(widget.tripId);
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

  void _handlePendingNavigation(DriverTripController controller) {
    final target = controller.pendingNavigation;
    if (target == DriverPendingNavigation.none) return;

    controller.consumePendingNavigation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (target == DriverPendingNavigation.inicioConductor) {
        _goToInicioConductor();
        return;
      }

      if (target == DriverPendingNavigation.rutaDestino) {
        _goToRutaDestino();
      }
    });
  }

  void _handleWaitingModal(DriverTripController controller) {
    if (controller.waitingModalVisible && !_waitingSheetVisible) {
      _scheduleOpenWaitingModal();
      return;
    }

    if (!controller.waitingModalVisible && _waitingSheetVisible) {
      _scheduleCloseWaitingModal();
    }
  }

  void _scheduleOpenWaitingModal() {
    if (_waitingModalOperationQueued || _waitingSheetVisible) return;
    _waitingModalOperationQueued = true;
    _waitingSheetVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _waitingModalOperationQueued = false;
      if (!mounted) {
        _waitingSheetVisible = false;
        return;
      }

      showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          _waitingModalContext = sheetContext;
          return ChangeNotifierProvider<DriverTripController>.value(
            value: _controller,
            child: Consumer<DriverTripController>(
              builder: (context, data, _) {
                return DriverWaitingClientModal(
                  remainingSeconds: data.waitingRemainingSeconds,
                  canStartTrip: data.waitingCanStartTrip,
                  isLoading: data.isWaitingActionLoading,
                  onStartTrip: () {
                    _onStartTripPressed(data);
                  },
                );
              },
            ),
          );
        },
      ).whenComplete(() {
        _waitingSheetVisible = false;
        _waitingModalContext = null;
      });
    });
  }

  void _scheduleCloseWaitingModal() {
    if (_waitingModalOperationQueued) return;
    _waitingModalOperationQueued = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _waitingModalOperationQueued = false;
      final modalCtx = _waitingModalContext;
      if (!mounted || modalCtx == null) return;

      try {
        Navigator.of(modalCtx).pop();
      } catch (_) {}
    });
  }

  Future<void> _onStartTripPressed(DriverTripController controller) async {
    try {
      final started = await controller.beginTripAfterClientConfirm();
      if (!started) return;
      if (!mounted) return;

      _closeWaitingModalImmediatelyIfOpen();
      await _goToRutaDestino(force: true);
    } catch (_) {
      // If Firestore update fails, the fallback navigation listener may still retry later.
    }
  }

  void _closeWaitingModalImmediatelyIfOpen() {
    final modalCtx = _waitingModalContext;
    if (modalCtx == null) return;

    try {
      Navigator.of(modalCtx).pop();
    } catch (_) {}

    _waitingSheetVisible = false;
    _waitingModalContext = null;
    _waitingModalOperationQueued = false;
  }

  Future<void> _goToRutaDestino({bool force = false}) async {
    if ((!force && _navigating) || !mounted) return;
    _navigating = true;

    try {
      await Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TripRouteTrackingScreen(
            solicitudId: widget.tripId,
            currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
            tipoUsuario: TipoUsuarioTracking.conductor,
          ),
        ),
      );
    } catch (_) {
      _navigating = false;
    }
  }

  Future<void> _goToInicioConductor() async {
    if (_navigating || !mounted) return;
    _navigating = true;

    try {
      await SessionHelper.clearActiveSolicitud();
      await RouteCacheService.clearSolicitud(widget.tripId);

      if (!mounted) return;

      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioConductor()),
        (route) => false,
      );
    } catch (_) {
      _navigating = false;
    }
  }
}
