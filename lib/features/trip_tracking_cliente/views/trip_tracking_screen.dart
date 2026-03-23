import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/features/trip_tracking_cliente/viewmodels/trip_route_tracking_viewmodel.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_route_tracking_screen.dart';
import 'package:taxi_app/core/services/services.dart';

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

class _TripTrackingScreenState extends State<TripTrackingScreen>
  with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  late final SolicitudEstadoController _estadoController;
  BitmapDescriptor? _taxiMarkerIcon;
  bool _initialCameraApplied = false;
  bool _cancelledNavigationDone = false;
  bool _rutaDestinoNavigationDone = false;
  bool _assignmentNotificationShown = false;
  String? _lastEstadoProcesado;
  String? _lastPersistedStatus;
  // Animated marker state for smooth movement
  LatLng? _animatedConductor;
  AnimationController? _markerAnimationController;
  Animation<LatLng>? _markerAnimation;
  String? _lastConductorTargetKey;
  double _conductorRotation = 0.0;
  static const double _snapThresholdMeters = 40.0;

  @override
  void initState() {
    super.initState();
    _estadoController = SolicitudEstadoController();
    _loadTaxiMarkerIcon();
    _showDriverAssignedNotification();
  }

  Future<void> _showDriverAssignedNotification() async {
    if (_assignmentNotificationShown) return;
    _assignmentNotificationShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
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

          // Mantener animacion suave del conductor (con umbral de snap)
          LatLng? markerTarget;
          if (vm.conductorLatLng != null) {
            final snapped = _snapToPolyline(vm.conductorLatLng!, vm.routePoints);
            final headingTarget = vm.routePoints.isNotEmpty
                ? _computePolylineHeading(snapped, vm.routePoints)
                : vm.conductorHeading;
            final meters = _metersBetween(vm.conductorLatLng!, snapped);
            final targetToUse = meters <= _snapThresholdMeters
                ? snapped
                : vm.conductorLatLng!;
            markerTarget = targetToUse;
            _syncAnimatedConductor(targetToUse, headingTarget);
          }

          final markers = <Marker>{
            if (vm.conductorLatLng != null)
              Marker(
                markerId: const MarkerId('conductor'),
                position: _animatedConductor ?? markerTarget ?? vm.conductorLatLng!,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon: _taxiMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                rotation: _conductorRotation,
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
                    bottom: isTablet ? 280 : 270,
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
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
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
    _markerAnimationController?.dispose();
    _mapController?.dispose();
    _estadoController.dispose();
    super.dispose();
  }

  void _syncAnimatedConductor(LatLng target, double headingTarget) {
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

  double _lerpAngle(double from, double to, double t) {
    final diff = ((to - from + 540) % 360) - 180;
    return _normalizeAngle(from + diff * t);
  }

  double _normalizeAngle(double angle) {
    final normalized = angle % 360;
    return normalized < 0 ? normalized + 360 : normalized;
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

  // Calcula el bearing (grados) a lo largo de la polyline cerca del punto "snapped".
  double _computePolylineHeading(LatLng snapped, List<LatLng> polyline) {
    if (polyline.length < 2) return 0.0;

    // Encuentra el vértice más cercano
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

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = (_radToDeg(math.atan2(y, x)) + 360) % 360;
    return bearing;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);
  double _radToDeg(double rad) => rad * (180.0 / math.pi);

  double _metersBetween(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius in meters
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
