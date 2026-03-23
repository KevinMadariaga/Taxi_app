import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:url_launcher/url_launcher.dart';

import '../viewmodels/trip_route_tracking_viewmodel.dart';
import '../widgets/trip_route_status_card.dart';
import '../widgets/trip_route_user_card.dart';

class TripRouteTrackingScreen extends StatefulWidget {
  const TripRouteTrackingScreen({
    super.key,
    required this.solicitudId,
    required this.currentUserId,
    required this.tipoUsuario,
  });

  final String solicitudId;
  final String currentUserId;
  final TipoUsuarioTracking tipoUsuario;

  @override
  State<TripRouteTrackingScreen> createState() =>
      _TripRouteTrackingScreenState();
}

class _TripRouteTrackingScreenState extends State<TripRouteTrackingScreen>
  with WidgetsBindingObserver, TickerProviderStateMixin {
  GoogleMapController? _mapController;
  BitmapDescriptor? _conductorMarkerIcon;
  BitmapDescriptor? _destinationMarkerIcon;

  LatLng? _animatedConductor;
  AnimationController? _markerAnimationController;
  Animation<LatLng>? _markerAnimation;
  String? _lastConductorTargetKey;
  double _conductorRotation = 0;
  static const double _snapThresholdMeters = 40.0;

  bool _initialCameraApplied = false;
  bool _navigatingToSummary = false;
  String? _lastPersistedStatus;
  bool _backgroundTrackingEnabled = false;
  bool _backgroundTrackingStarting = false;
  bool _activeTripNotificationShown = false;

  bool get _isConductorRole =>
      widget.tipoUsuario == TipoUsuarioTracking.conductor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConductorMarkerIcon();
    _loadDestinationMarkerIcon();
    _showActiveTripNotificationOnLoad();
  }

  Future<void> _loadConductorMarkerIcon() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;

      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(22, 42), devicePixelRatio: dpr),
        'assets/img/taxi_icon.png',
      );

      if (!mounted) return;
      setState(() {
        _conductorMarkerIcon = icon;
      });
    } catch (_) {
      // Keep default marker if custom asset fails to load.
    }
  }

  Future<void> _loadDestinationMarkerIcon() async {
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
        _destinationMarkerIcon = icon;
      });
    } catch (_) {
      // Keep default marker if custom asset fails to load.
    }
  }

  Future<void> _showActiveTripNotificationOnLoad() async {
    if (!_isConductorRole || _activeTripNotificationShown) return;
    _activeTripNotificationShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.instance.init();
        await NotificationService.instance.showNotification(
          DateTime.now().millisecondsSinceEpoch % 100000,
          'Viaje activo',
          'Lleva al cliente a su destino.',
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (_isConductorRole) {
      _stopBackgroundTrackingIfNeeded();
      try {
        NotificacionesServicio.instance.cancelAll();
      } catch (_) {}
    }
    WidgetsBinding.instance.removeObserver(this);
    _markerAnimationController?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_isConductorRole) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _startBackgroundTrackingIfNeeded();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _stopBackgroundTrackingIfNeeded();
    }
  }

  Future<void> _startBackgroundTrackingIfNeeded() async {
    if (!_isConductorRole) return;
    if (_backgroundTrackingEnabled || _backgroundTrackingStarting) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _backgroundTrackingStarting = true;

    try {
      await initializeBackgroundService();
      await startBackgroundTrackingService();
      final service = FlutterBackgroundService();

      // Give the isolate a moment to register listeners before sending command.
      await Future<void>.delayed(const Duration(milliseconds: 450));

      service.invoke('startTracking', {
        'userId': uid,
        'userType': 'conductor',
        'solicitudId': widget.solicitudId,
      });
      _backgroundTrackingEnabled = true;
    } catch (_) {
      _backgroundTrackingEnabled = false;
    } finally {
      _backgroundTrackingStarting = false;
    }
  }

  Future<void> _stopBackgroundTrackingIfNeeded() async {
    if (!_isConductorRole) return;
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
    } catch (_) {}
    _backgroundTrackingEnabled = false;
    _backgroundTrackingStarting = false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TripRouteTrackingViewModel>(
      create: (_) => TripRouteTrackingViewModel(
        solicitudId: widget.solicitudId,
        currentUserId: widget.currentUserId,
        tipoUsuario: widget.tipoUsuario,
      )..init(),
      child: Consumer<TripRouteTrackingViewModel>(
        builder: (context, vm, _) {
          _syncSolicitudPersistence(vm);
          // Snap conductor GPS to visible route and compute heading along polyline
          if (vm.conductorLatLng != null) {
            final snapped = _snapToPolyline(vm.conductorLatLng!, vm.visibleRoutePoints);
            final headingTarget = vm.visibleRoutePoints.isNotEmpty
                ? _computePolylineHeading(snapped, vm.visibleRoutePoints)
                : vm.conductorHeading;
            final meters = _metersBetween(vm.conductorLatLng!, snapped);
            final targetToUse = meters <= _snapThresholdMeters ? snapped : vm.conductorLatLng!;
            _syncAnimatedConductor(targetToUse, vm.destinoLatLng, headingTarget);
          } else {
            _syncAnimatedConductor(vm.conductorLatLng, vm.destinoLatLng, vm.conductorHeading);
          }
          _fitCameraIfNeeded(vm);
          _handleCompletionNavigation(vm);

          final conductorToShow = _animatedConductor ?? vm.conductorLatLng;
          final visibleRoutePoints = vm.visibleRoutePoints;
          final markers = <Marker>{
            if (conductorToShow != null)
              Marker(
                markerId: const MarkerId('conductor_tracking'),
                position: conductorToShow,
                rotation: _conductorRotation,
                anchor: const Offset(0.5, 0.5),
                flat: true,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon:
                    _conductorMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
              ),
            if (vm.destinoLatLng != null)
              Marker(
                markerId: const MarkerId('destino_tracking'),
                position: vm.destinoLatLng!,
                infoWindow: const InfoWindow(title: 'Destino'),
                icon:
                    _destinationMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
              ),
          };

          final polylines = <Polyline>{
            if (visibleRoutePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('trip_route_polyline'),
                points: visibleRoutePoints,
                color: AppColores.buttonPrimary,
                width: 6,
              ),
          };

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Mapagoogle(
                              initialTarget:
                                  conductorToShow ??
                                  vm.destinoLatLng ??
                                  const LatLng(8.2595534, -73.353469),
                              initialZoom: 14,
                              markers: markers,
                              polylines: polylines,
                              myLocationEnabled: false,
                              myLocationButtonEnabled: false,
                              onMapCreated: (controller) {
                                _mapController = controller;
                                _fitCameraIfNeeded(vm);
                              },
                            ),
                          ),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: TripRouteStatusCard(
                                etaText: vm.etaText,
                                distanceText: vm.distanceText,
                                isOffline: vm.isOffline,
                                isSyncingPending: vm.isSyncingPendingLocations,
                              ),
                            ),
                          ),
                          if (vm.isOffline)
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 74,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColores.warning,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.wifi_off_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        vm.offlineText,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            right: 16,
                            bottom: 92,
                            child: FloatingActionButton(
                              heroTag: 'trip_route_panic_button',
                              backgroundColor: AppColores.buttonCancel,
                              onPressed: _onPanicPressed,
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16,
                            bottom: 20,
                            child: FloatingActionButton(
                              heroTag: 'trip_route_focus_button',
                              backgroundColor: AppColores.primary,
                              onPressed: () => _onFocusPressed(vm),
                              child: Icon(
                                vm.focusMode == RouteTrackingFocusMode.destino
                                    ? Icons.flag
                                    : Icons.fit_screen,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (vm.isLoading || vm.isCompletingTrip)
                            Positioned.fill(
                              child: ColoredBox(
                                color: AppColores.overlayLight,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                        color: AppColores.primary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        vm.isCompletingTrip
                                            ? 'Terminando viaje...'
                                            : 'Cargando seguimiento...',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TripRouteUserCard(
                      title: widget.tipoUsuario == TipoUsuarioTracking.conductor
                          ? 'Informacion del cliente'
                          : 'Informacion del conductor',
                      userName: vm.userDisplayName,
                      userPhotoUrl: vm.userPhotoUrl,
                      vehiclePlate: vm.vehiclePlate,
                      vehiclePhotoUrl: vm.vehiclePhotoUrl,
                      destinationText: vm.destinationText,
                      onSharePressed: () => _onSharePressed(vm),
                      onSecondaryActionPressed: () => vm.isConductor
                          ? _onOpenRouteInGoogleMaps(vm)
                          : _onPanicPressed(),
                      secondaryActionLabel: vm.isConductor
                          ? 'Abrir Mapa'
                          : 'Panico',
                      secondaryActionIcon: vm.isConductor
                          ? Icons.map_outlined
                          : Icons.warning_amber_rounded,
                      secondaryActionColor: vm.isConductor
                          ? AppColores.buttonPrimary
                          : AppColores.buttonCancel,
                      showSecondaryAction: vm.isConductor,
                      showVehicleInfo: !vm.isConductor,
                      showActionButtons: true,
                      showCompleteTripButton: vm.isConductor,
                      onCompleteTripPressed: vm.isCompletingTrip
                          ? null
                          : () async {
                              try {
                                await vm.finalizarViajePorConductor();
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo terminar el viaje. Intenta nuevamente.',
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _syncAnimatedConductor(LatLng? target, LatLng? destination, double headingTarget) {
    if (target == null) return;

    final key = '${target.latitude.toStringAsFixed(7)},${target.longitude.toStringAsFixed(7)}';
    if (_lastConductorTargetKey == key) return;
    _lastConductorTargetKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final from = _animatedConductor ?? target;

      _markerAnimationController?.stop();
      _markerAnimationController?.dispose();

      _markerAnimationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );

      _markerAnimation = LatLngTween(begin: from, end: target).animate(
        CurvedAnimation(parent: _markerAnimationController!, curve: Curves.easeOut),
      )..addListener(() {
          if (!mounted) return;
          setState(() {
            _animatedConductor = _markerAnimation!.value;
            _conductorRotation = _lerpAngle(_conductorRotation, headingTarget, 0.45);
          });
        });

      _markerAnimationController!.forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _conductorRotation = headingTarget;
        });
      });
    });
  }

  Future<void> _onFocusPressed(TripRouteTrackingViewModel vm) async {
    final map = _mapController;
    if (map == null) return;

    if (vm.focusMode == RouteTrackingFocusMode.ambos) {
      final destination = vm.destinoLatLng;
      if (destination != null) {
        await map.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: destination, zoom: 15.5, tilt: 0),
          ),
        );
      }
      await vm.toggleFocusMode();
      return;
    }

    final conductor = _animatedConductor ?? vm.conductorLatLng;
    final destination = vm.destinoLatLng;
    if (conductor != null && destination != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(conductor.latitude, destination.latitude),
          math.min(conductor.longitude, destination.longitude),
        ),
        northeast: LatLng(
          math.max(conductor.latitude, destination.latitude),
          math.max(conductor.longitude, destination.longitude),
        ),
      );
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
    }

    await vm.toggleFocusMode();
  }

  void _fitCameraIfNeeded(TripRouteTrackingViewModel vm) {
    if (_initialCameraApplied) return;
    final map = _mapController;
    final conductor = _animatedConductor ?? vm.conductorLatLng;
    final destination = vm.destinoLatLng;

    if (map == null || conductor == null || destination == null) return;

    _initialCameraApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(conductor.latitude, destination.latitude),
          math.min(conductor.longitude, destination.longitude),
        ),
        northeast: LatLng(
          math.max(conductor.latitude, destination.latitude),
          math.max(conductor.longitude, destination.longitude),
        ),
      );
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
    });
  }

  void _syncSolicitudPersistence(TripRouteTrackingViewModel vm) {
    final normalized = _normalizeEstado(vm.estadoSolicitud);
    if (normalized.isEmpty) return;
    if (_lastPersistedStatus == normalized) return;
    _lastPersistedStatus = normalized;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_shouldPersistSolicitud(normalized)) {
        try {
          await SessionHelper.setActiveSolicitud(widget.solicitudId);
          await RouteCacheService.saveForSolicitud(
            RouteCacheData(
              solicitudId: widget.solicitudId,
              role: vm.isConductor ? 'conductor' : 'cliente',
              clientName: vm.isConductor ? vm.userDisplayName : null,
              clientAddress: vm.destinationText,
              conductorId: vm.isConductor ? widget.currentUserId : null,
              conductorName: vm.isConductor ? null : vm.userDisplayName,
              conductorPlate: vm.vehiclePlate,
              conductorVehiclePhotoUrl: vm.vehiclePhotoUrl,
            ),
          );
        } catch (_) {}
        return;
      }

      if (_shouldClearSolicitud(normalized)) {
        try {
          await SessionHelper.clearActiveSolicitud();
          await RouteCacheService.clearSolicitud(widget.solicitudId);
          try {
            await _stopBackgroundTrackingIfNeeded();
          } catch (_) {}
          try {
            await NotificacionesServicio.instance.cancelAll();
          } catch (_) {}
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

  String _normalizeEstado(String rawEstado) {
    return SolicitudEstado.normalize(rawEstado);
  }

  void _handleCompletionNavigation(TripRouteTrackingViewModel vm) {
    if (_navigatingToSummary || !vm.shouldNavigateToSummary) return;

    _navigatingToSummary = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      vm.consumeSummaryNavigation();

      final bool isDriver = widget.tipoUsuario == TipoUsuarioTracking.conductor;
      unawaited(_clearTripSessionCache());
      // Navigate without awaiting to avoid blocking UI/frame
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isDriver
              ? ResumenConductorView(solicitudId: widget.solicitudId)
              : ResumenClienteView(solicitudId: widget.solicitudId),
        ),
      );
    });
  }

  Future<void> _clearTripSessionCache() async {
    try {
      await SessionHelper.clearActiveSolicitud();
      await RouteCacheService.clearSolicitud(widget.solicitudId);
    } catch (_) {}
  }

  Future<void> _onSharePressed(TripRouteTrackingViewModel vm) async {
    final url = vm.shareLocationUrl;
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ubicacion no disponible')));
      return;
    }

    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Compartir ubicacion',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () async {
                    await launchUrl(Uri.parse(url));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  icon: const Icon(Icons.map),
                  label: const Text('Google Maps'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final encoded = Uri.encodeComponent(
                      'Ubicacion del conductor: $url',
                    );
                    final whatsapp = Uri.parse('https://wa.me/?text=$encoded');
                    if (await canLaunchUrl(whatsapp)) {
                      await launchUrl(whatsapp);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onOpenRouteInGoogleMaps(TripRouteTrackingViewModel vm) async {
    final origen = _animatedConductor ?? vm.conductorLatLng;
    final destino = vm.destinoLatLng;
    if (origen == null || destino == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ruta no disponible')));
      return;
    }

    final nativeUri = Uri.parse(
      'google.navigation:q=${destino.latitude},${destino.longitude}&mode=d',
    );

    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=${origen.latitude},${origen.longitude}&destination=${destino.latitude},${destino.longitude}&travelmode=driving',
    );

    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      return;
    }

    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  // Proyecta la posición GPS sobre la polyline y devuelve el punto "snapped".
  LatLng _snapToPolyline(LatLng gps, List<LatLng> polyline) {
    if (polyline.isEmpty) return gps;
    if (polyline.length == 1) return polyline.first;

    double minDist = double.infinity;
    LatLng best = polyline.first;

    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final proj = _projectPointOnSegment(gps, a, b);
      final d = _distance2D(proj, gps);
      if (d < minDist) {
        minDist = d;
        best = proj;
      }
    }

    return best;
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final x1 = a.longitude;
    final y1 = a.latitude;
    final x2 = b.longitude;
    final y2 = b.latitude;
    final x3 = p.longitude;
    final y3 = p.latitude;

    final dx = x2 - x1;
    final dy = y2 - y1;
    final denom = dx * dx + dy * dy;
    if (denom == 0) return a;

    var t = ((x3 - x1) * dx + (y3 - y1) * dy) / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    final projLon = x1 + t * dx;
    final projLat = y1 + t * dy;
    return LatLng(projLat, projLon);
  }

  double _distance2D(LatLng a, LatLng b) {
    final dx = a.longitude - b.longitude;
    final dy = a.latitude - b.latitude;
    return math.sqrt(dx * dx + dy * dy);
  }

  // Calcula el heading usando el segmento más cercano de la polyline.
  double _computePolylineHeading(LatLng snapped, List<LatLng> polyline) {
    if (polyline.length < 2) return 0.0;

    int nearestIndex = 0;
    double minDist = double.infinity;
    for (var i = 0; i < polyline.length; i++) {
      final d = _distance2D(snapped, polyline[i]);
      if (d < minDist) {
        minDist = d;
        nearestIndex = i;
      }
    }

    LatLng from;
    LatLng to;
    if (nearestIndex < polyline.length - 1) {
      from = polyline[nearestIndex];
      to = polyline[nearestIndex + 1];
    } else {
      from = polyline[nearestIndex - 1];
      to = polyline[nearestIndex];
    }

    return _bearingBetween(from, to);
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

  double _bearingBetween(LatLng from, LatLng to) {
    final dy = to.latitude - from.latitude;
    final dx = to.longitude - from.longitude;
    return _normalizeAngle(math.atan2(dx, dy) * 180 / math.pi);
  }

  double _lerpAngle(double from, double to, double t) {
    final diff = ((to - from + 540) % 360) - 180;
    return _normalizeAngle(from + diff * t);
  }

  double _normalizeAngle(double angle) {
    final normalized = angle % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  double _metersBetween(LatLng a, LatLng b) {
    const R = 6371000.0; // meters
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLat = lat2 - lat1;
    final dLon = _degToRad(b.longitude - a.longitude);
    final hav = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(hav), math.sqrt(1 - hav));
    return R * c;
  }

}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({LatLng? begin, LatLng? end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    final lat = begin!.latitude + (end!.latitude - begin!.latitude) * t;
    final lon = begin!.longitude + (end!.longitude - begin!.longitude) * t;
    return LatLng(lat, lon);
  }
}
