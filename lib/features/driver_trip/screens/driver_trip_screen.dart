import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaDestinoView.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/trip_details_sheet.dart';
import 'package:taxi_app/core/services/services.dart';

import '../controllers/driver_trip_controller.dart';
import '../widgets/driver_client_info_card.dart';
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
  BitmapDescriptor? _clientMarkerIcon;

  bool _initialCameraApplied = false;
  bool _navigating = false;
  bool _waitingSheetVisible = false;
  bool _waitingModalOperationQueued = false;
  BuildContext? _waitingModalContext;
  String? _lastPersistedStatus;
  bool _backgroundTrackingEnabled = false;
  bool _backgroundTrackingStarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = DriverTripController(tripId: widget.tripId);
    _loadClientMarkerIcon();
    _controller.init();
    // Persist current screen so reload restores DriverTripScreen when assigned
    try {
      SessionHelper.setActiveSolicitudScreen('driver_trip');
    } catch (_) {}
  }

  Future<void> _loadClientMarkerIcon() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() {
        _clientMarkerIcon = icon;
      });
    } catch (_) {}
  }

  /// Detecta si el dispositivo tiene barra de navegación inferior (Android/iOS)
  bool hasNavigationBar(BuildContext context) {
    return MediaQuery.of(context).padding.bottom > 0;
  }

  @override
  void dispose() {
    _stopBackgroundTrackingIfNeeded();
    try {
      NotificacionesServicio.instance.cancelAll();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller.setAppBackground(true);
      _startBackgroundTrackingIfNeeded();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _controller.setAppBackground(false);
      _stopBackgroundTrackingIfNeeded();
      _controller.onAppResumed();
    }
  }

  Future<void> _startBackgroundTrackingIfNeeded() async {
    if (_backgroundTrackingEnabled || _backgroundTrackingStarting) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _backgroundTrackingStarting = true;

    try {
      await initializeBackgroundService();
      await startBackgroundTrackingService();
      final service = FlutterBackgroundService();

      // Give the isolate a short moment to register listeners before sending the command.
      await Future<void>.delayed(const Duration(milliseconds: 450));

      service.invoke('startTracking', {
        'userId': uid,
        'userType': 'conductor',
        'solicitudId': widget.tripId,
      });
      _backgroundTrackingEnabled = true;
    } catch (_) {
      _backgroundTrackingEnabled = false;
    } finally {
      _backgroundTrackingStarting = false;
    }
  }

  Future<void> _stopBackgroundTrackingIfNeeded() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
    } catch (_) {}
    _backgroundTrackingEnabled = false;
    _backgroundTrackingStarting = false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DriverTripController>.value(
      value: _controller,
      child: Consumer<DriverTripController>(
        builder: (context, controller, _) {
          // Notification and persistence logic
          void handlePersistenceAndNotifications() async {
            final rawStatus = controller.trip?.status;
            if (rawStatus == null || rawStatus.trim().isEmpty) return;
            final status = DriverTripController.normalizeStatus(rawStatus);
            if (_lastPersistedStatus == status) return;
            _lastPersistedStatus = status;
            if (status == 'cancelado') {
              try {
                await NotificacionesServicio.instance.showTripNotification(
                  title: 'Servicio cancelado',
                  body: 'El cliente ha cancelado el servicio.',
                );
              } catch (_) {}
            }
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
                  try {
                    await _stopBackgroundTrackingIfNeeded();
                  } catch (_) {}
                  try {
                    await NotificacionesServicio.instance.cancelAll();
                  } catch (_) {}
                  await SessionHelper.clearActiveSolicitud();
                  await RouteCacheService.clearSolicitud(widget.tripId);
                } catch (_) {}
              }
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            handlePersistenceAndNotifications();
          });
          _handlePendingNavigation(controller);
          _handleWaitingModal(controller);
          _fitInitialCameraIfNeeded(controller);

          final markers = <Marker>{
            if (controller.clientLatLng != null)
              Marker(
                markerId: const MarkerId('client_marker'),
                position: controller.clientLatLng!,
                infoWindow: const InfoWindow(title: 'Cliente'),
                icon:
                    _clientMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                anchor: const Offset(0.5, 0.5),
              ),
          };

          final polylines = <Polyline>{
            if (controller.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('driver_trip_route'),
                points: controller.routePoints,
                color: AppColores.buttonPrimary,
                width: 5,
              ),
          };

          final fallback = const LatLng(8.2595534, -73.353469);
          final initialTarget =
              controller.clientLatLng ?? controller.driverLatLng ?? fallback;

          final currStatus = controller.trip?.status ?? '';
          String dynamicTitle = 'Conectando...';
          if (currStatus.contains('asignado') ||
              currStatus.contains('en_espera') ||
              currStatus.contains('en_camino')) {
            dynamicTitle = 'Dirigiéndote al cliente';
          } else if (currStatus.contains('en_ruta')) {
            dynamicTitle = 'En viaje hacia el destino';
          } else {
            dynamicTitle = 'Viaje Activo';
          }

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: PopScope(
              canPop: false,
              child: Scaffold(
                body: Builder(
                  builder: (ctx) {
                    final mq = MediaQuery.of(ctx);
                    final hasNavBar = hasNavigationBar(ctx);

                    return Stack(
                      children: [
                        Stack(
                          children: [
                            Positioned.fill(
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: initialTarget,
                                  zoom: 14,
                                ),
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                markers: markers,
                                polylines: polylines,
                                // Add higher top padding to shift the map's visual center
                                // significantly downwards, avoiding the large expanded info card.
                                padding: const EdgeInsets.only(
                                  top: 350,
                                  bottom: 20,
                                ),
                                onMapCreated: (map) {
                                  _mapController = map;
                                  _fitInitialCameraIfNeeded(controller);
                                },
                              ),
                            ),
                            Positioned(
                              left: 16,
                              bottom: hasNavBar ? mq.padding.bottom + 16 : 32,
                              child: FloatingActionButton(
                                heroTag: 'driver_trip_panic_btn',
                                backgroundColor: AppColores.buttonCancel,
                                onPressed: _onPanicPressed,
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColores.textWhite,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              bottom: hasNavBar ? mq.padding.bottom + 88 : 104,
                              child: FloatingActionButton(
                                heroTag: 'driver_map_focus_btn',
                                backgroundColor: AppColores.buttonPrimary,
                                onPressed: () => _toggleFocus(controller),
                                child: Icon(
                                  controller.focusMode ==
                                          DriverMapFocusMode.clientOnly
                                      ? Icons.person_pin_circle
                                      : Icons.fit_screen,
                                  color: AppColores.textWhite,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: DriverClientInfoCard(
                                clientName: controller.clientName,
                                clientAddress: controller.clientAddress,
                                clientPhotoUrl: controller.clientPhotoUrl,
                                unreadCount: controller.unreadCount,
                                onOpenChat: () => _openChat(controller),
                                onOpenNavigation: () =>
                                    _openNavigation(controller),
                                onReportArrival: controller.reportArrival,
                                isSendingArrival: controller.isSendingArrival,
                                isArrivalReported:
                                    controller.hasReportedArrival,
                                arrivalButtonEnabled:
                                    controller.distanceMeters != null &&
                                    controller.distanceMeters! <= 50,
                                etaText: controller.etaText,
                                distanceText: controller.distanceText,
                                title: dynamicTitle,
                                onDetails: () => _openDetails(controller),
                              ),
                            ),
                          ],
                        ),

                        if (controller.isLoading || controller.isRouteLoading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.6),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: AppColores.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Cargando ruta...',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
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

  void _openDetails(DriverTripController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TripDetailsSheet(
        tituloPersona: 'Cliente',
        nombrePersona: controller.clientName,
        fotoPersona: controller.clientPhotoUrl,
        calificacion: 0,
        totalCalificaciones: 0,
        fotoVehiculo: '',
        placa: '',
        direccionRecoger: controller.clientAddress,
        direccionDestino: controller.destinoDireccion,
        valorServicio: controller.valorServicio,
        metodoPago: controller.metodoPago,
        mostrarVehiculo: false,
        mostrarCalificacion: false,
      ),
    );
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
      final persp = controller.getCameraPerspective();
      if (persp != null) {
        await map.animateCamera(CameraUpdate.newCameraPosition(persp));
      } else {
        final target = controller.clientLatLng;
        if (target != null) {
          await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
        }
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

  void _onPanicPressed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Centro de seguridad',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Selecciona una opcion de ayuda rapida.',
                  style: TextStyle(color: AppColores.textSecondary),
                ),
                SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sos, color: AppColores.buttonCancel),
                  title: Text(
                    'Emergencia',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Solicitar asistencia urgente.'),
                ),
                Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.report_problem_outlined),
                  title: Text(
                    'Reportar problema',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Reportar incidente durante el viaje.'),
                ),
                Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.support_agent_outlined),
                  title: Text(
                    'Contactar soporte',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Hablar con soporte de Taxi App.'),
                ),
              ],
            ),
          ),
        );
      },
    );
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

      final persp = controller.getCameraPerspective();
      if (persp != null) {
        await map.animateCamera(CameraUpdate.newCameraPosition(persp));
      } else {
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
        // Using a smaller padding here because Map padding already shifts the center
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
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
        status.contains('sin_respu') ||
        status.contains('complet') ||
        status.contains('finaliz');
  }

  void _handlePendingNavigation(DriverTripController controller) {
    final target = controller.pendingNavigation;
    if (target == DriverPendingNavigation.none) return;

    final infoMessage = controller.consumePendingInfoMessage();
    controller.consumePendingNavigation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (target == DriverPendingNavigation.inicioConductor) {
        _goToInicioConductorWithMessage(infoMessage);
        return;
      }

      if (target == DriverPendingNavigation.rutaDestino) {
        _goToRutaDestino();
      }
    });
  }

  Future<void> _goToInicioConductorWithMessage(String? message) async {
    // El mensaje (motivo) ya se comunica con la pantalla intermedia
    // "Solicitud cancelada" dentro de _goToInicioConductor.
    if (!mounted) return;
    await _goToInicioConductor();
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
      try {
        await SessionHelper.setActiveSolicitudScreen('ruta_destino');
      } catch (_) {}
      if (!mounted) return;
      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => RutaDestino(idSolicitud: widget.tripId),
        title: 'Viajando hacia el destino',
        subtitle: 'Llevando al cliente a su destino.',
        icon: Icons.navigation_rounded,
        accentColor: AppColores.buttonPrimary,
        drawCheck: false,
        delay: const Duration(milliseconds: 1500),
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
      try {
        await SessionHelper.clearActiveSolicitudScreen();
      } catch (_) {}
      await RouteCacheService.clearSolicitud(widget.tripId);

      if (!mounted) return;

      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const InicioConductor(),
        title: 'Solicitud cancelada',
        subtitle: 'El servicio fue cancelado.',
        icon: Icons.close_rounded,
        accentColor: AppColores.error,
        drawCheck: false,
        delay: const Duration(milliseconds: 1600),
        clearStackOnNext: true,
      );
    } catch (_) {
      _navigating = false;
    }
  }
}
