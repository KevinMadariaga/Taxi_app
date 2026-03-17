import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
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
  State<TripRouteTrackingScreen> createState() => _TripRouteTrackingScreenState();
}

class _TripRouteTrackingScreenState extends State<TripRouteTrackingScreen> {
  GoogleMapController? _mapController;

  LatLng? _animatedConductor;
  Timer? _markerAnimationTimer;
  String? _lastConductorTargetKey;
  double _conductorRotation = 0;

  bool _initialCameraApplied = false;
  bool _navigatingToSummary = false;
  String? _lastPersistedStatus;

  @override
  void dispose() {
    _markerAnimationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
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
          _syncAnimatedConductor(vm.conductorLatLng, vm.destinoLatLng);
          _fitCameraIfNeeded(vm);
          _handleCompletionNavigation(vm);

          final conductorToShow = _animatedConductor ?? vm.conductorLatLng;
          final markers = <Marker>{
            if (conductorToShow != null)
              Marker(
                markerId: const MarkerId('conductor_tracking'),
                position: conductorToShow,
                rotation: _conductorRotation,
                anchor: const Offset(0.5, 0.5),
                flat: true,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),
            if (vm.destinoLatLng != null)
              Marker(
                markerId: const MarkerId('destino_tracking'),
                position: vm.destinoLatLng!,
                infoWindow: const InfoWindow(title: 'Destino'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
              ),
          };

          final polylines = <Polyline>{
            if (vm.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('trip_route_polyline'),
                points: vm.routePoints,
                color: AppColores.buttonPrimary,
                width: 6,
              ),
          };

          return Scaffold(
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
                      ? 'Abrir mapa'
                      : 'Panico',
                    secondaryActionIcon: vm.isConductor
                      ? Icons.map_outlined
                      : Icons.warning_amber_rounded,
                    secondaryActionColor: vm.isConductor
                      ? AppColores.buttonChat
                      : AppColores.buttonCancel,
                    showSecondaryAction: vm.isConductor,
                    showVehicleInfo: !vm.isConductor,
                    showActionButtons: true,
                    showCompleteTripButton: vm.isConductor,
                    onCompleteTripPressed: vm.isCompletingTrip
                        ? null
                        : () async {
                            await vm.finalizarViajePorConductor();
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _syncAnimatedConductor(LatLng? target, LatLng? destination) {
    if (target == null) return;

    final key =
        '${target.latitude.toStringAsFixed(7)},${target.longitude.toStringAsFixed(7)}';
    if (_lastConductorTargetKey == key) return;
    _lastConductorTargetKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final current = _animatedConductor;
      if (current == null) {
        setState(() {
          _animatedConductor = target;
        });
        return;
      }

      _markerAnimationTimer?.cancel();

      final from = current;
      final to = target;
      final heading = _bearingBetween(from, to);
      const totalTicks = 18;
      var tick = 0;

      _markerAnimationTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        (timer) {
          tick += 1;
          final t = (tick / totalTicks).clamp(0.0, 1.0);

          final lat = from.latitude + ((to.latitude - from.latitude) * t);
          final lng = from.longitude + ((to.longitude - from.longitude) * t);

          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _animatedConductor = LatLng(lat, lng);
            _conductorRotation = _lerpAngle(_conductorRotation, heading, 0.45);
          });

          if (t >= 1.0) {
            timer.cancel();
            if (destination != null) {
              setState(() {
                _conductorRotation = _bearingBetween(to, destination);
              });
            }
          }
        },
      );
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
        } catch (_) {}
      }
    });
  }

  bool _shouldPersistSolicitud(String status) {
    return status == 'en_ruta' ||
        status == 'en_camino' ||
        status == 'en_espera' ||
        status == 'asignado';
  }

  bool _shouldClearSolicitud(String status) {
    return status == 'cancelado' ||
        status.contains('complet') ||
        status.contains('finaliz');
  }

  String _normalizeEstado(String rawEstado) {
    final raw = rawEstado.toLowerCase().trim();
    final compact = raw.replaceAll('_', ' ').replaceAll('-', ' ');

    if (compact.contains('en ruta') || compact.contains('enruta')) {
      return 'en_ruta';
    }
    if (compact.contains('en camino') || compact.contains('encam')) {
      return 'en_camino';
    }
    if (compact.contains('en espera') || compact.contains('enespera')) {
      return 'en_espera';
    }
    if (compact.contains('asignado') || compact.contains('assigned')) {
      return 'asignado';
    }
    if (compact.contains('cancel')) {
      return 'cancelado';
    }
    if (compact.contains('complet') || compact.contains('finaliz')) {
      return 'completado';
    }

    return compact;
  }

  void _handleCompletionNavigation(TripRouteTrackingViewModel vm) {
    if (_navigatingToSummary || !vm.shouldNavigateToSummary) return;

    _navigatingToSummary = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      try {
        await SessionHelper.clearActiveSolicitud();
        await RouteCacheService.clearSolicitud(widget.solicitudId);
      } catch (_) {}

      if (!mounted) return;

      vm.consumeSummaryNavigation();

      final bool isDriver = widget.tipoUsuario == TipoUsuarioTracking.conductor;
      await navigateWithIntermediateLoader(
        context: context,
        title: 'Terminando viaje...',
        subtitle: isDriver
            ? 'Preparando resumen del conductor...'
            : 'Preparando resumen del viaje...',
        delay: const Duration(milliseconds: 1300),
        nextBuilder: (_) => isDriver
            ? ResumenConductorView(solicitudId: widget.solicitudId)
            : ResumenClienteView(solicitudId: widget.solicitudId),
      );
    });
  }

  Future<void> _onSharePressed(TripRouteTrackingViewModel vm) async {
    final url = vm.shareLocationUrl;
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicacion no disponible')),
      );
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
                    backgroundColor: AppColores.buttonChat,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ruta no disponible')),
      );
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
}
