
import 'dart:async';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/services/route_cache_service.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/firebase_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/user_trip_info_card.dart';

class RutaClienteDestino extends StatelessWidget {
  final String idSolicitud;
  const RutaClienteDestino({Key? key, required this.idSolicitud})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var hasProvider = true;
    try {
      Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
    } catch (_) {
      hasProvider = false;
    }

    if (hasProvider) {
      return _RutaClienteDestinoContent(idSolicitud: idSolicitud);
    }

    return ChangeNotifierProvider<Rutaclientedestinoviewmodel>(
      create: (_) => Rutaclientedestinoviewmodel(),
      child: _RutaClienteDestinoContent(idSolicitud: idSolicitud),
    );
  }
}

class _RutaClienteDestinoContent extends StatefulWidget {
  final String idSolicitud;
  const _RutaClienteDestinoContent({Key? key, required this.idSolicitud})
      : super(key: key);

  @override
  State<_RutaClienteDestinoContent> createState() =>
      _RutaClienteDestinoContentState();
}

class _RutaClienteDestinoContentState extends State<_RutaClienteDestinoContent> with WidgetsBindingObserver {
  // =====================
  // UI & System Styles
  // =====================
  static const SystemUiOverlayStyle _rutaClienteDestinoOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.white,
    systemNavigationBarContrastEnforced: false,
  );

  // =====================
  // State & Controllers
  // =====================
  Rutaclientedestinoviewmodel? _viewModel;
  GoogleMapController? _mapController;
  Timer? _animacionMarcadorTimer;
  StreamSubscription<LatLng?>? _conductorLocationSub;
  StreamSubscription? _conductorLocationFirestoreSub;

  // =====================
  // Map & Route State
  // =====================
  LatLng? _conductorLatLng;
  LatLng? _lastConductorLatLng;
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _conductorMarkerIcon;
  BitmapDescriptor? _destinoMarkerIcon;
  double _conductorRotation = 0;
  String _distancia = '';

  // =====================
  // UI State
  // =====================
  bool _mostrarSoloDestino = false;
  bool _isUpdatingRoute = false;
  bool _isRouteListenerAttached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_rutaClienteDestinoOverlayStyle);
    _viewModel = Provider.of<Rutaclientedestinoviewmodel>(
      context,
      listen: false,
    );
    debugPrint(
      '[RutaClienteDestinoView] Escuchando ubicación del conductor para solicitud: ${widget.idSolicitud}',
    );
    _viewModel!.escucharUbicacionConductor(widget.idSolicitud);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await SessionHelper.setActiveSolicitud(widget.idSolicitud);
      try { await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino'); } catch (_) {}
            try {
              await SessionHelper.clearActiveSolicitud();
              try { await SessionHelper.clearActiveSolicitudScreen(); } catch (_) {}
              await RouteCacheService.clearSolicitud(widget.idSolicitud);
            } catch (_) {}
      // Persist that the user is on the RutaClienteDestino screen so reload
      // keeps this exact view when the solicitud está 'asignado'.
      try {
        await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino');
      } catch (_) {}
      _viewModel!.inicializarNotificaciones();
      await _viewModel!.mostrarNotificacion(
        '🚕 Ruta iniciada',
        'Se comenzó la ruta hacia el destino. ¡Prepárate para llegar!',
      );
      if (!mounted) return;
      await _viewModel!.cargarDatosConductorYUbicacionDestino(
        widget.idSolicitud,
      );
      await _cargarMarcadoresPersonalizados();
      _viewModel!.escucharEstadoSolicitud(widget.idSolicitud, context);

      if (!_isRouteListenerAttached) {
        _viewModel!.addListener(_actualizarRuta);
        _isRouteListenerAttached = true;
      }

      // Llamar una vez al inicio
      await _actualizarRuta();

      // Suscribirse a cambios en la solicitud para actualizar ubicación del conductor en tiempo real
      try {
        final svc = TripTrackingFirebaseService();
        _conductorLocationFirestoreSub = svc.watchSolicitudRaw(widget.idSolicitud).listen((data) {
          if (!mounted) return;
          try {
            final conductor = data['conductor'];
            if (conductor is Map) {
              final ubic = conductor['ubicacion'];
              if (ubic is Map) {
                final lat = (ubic['lat'] as num).toDouble();
                final lng = (ubic['lng'] as num).toDouble();
                final newPos = LatLng(lat, lng);
                setState(() {
                  _conductorLatLng = newPos;
                  _lastConductorLatLng = newPos;
                });
              }
            }

            // Si hay historial de tracking, actualizar polyline
            final tracking = data['tracking'];
            if (tracking is Map) {
              final driverHistory = tracking['driverHistory'];
              if (driverHistory is List && driverHistory.isNotEmpty) {
                final points = <LatLng>[];
                for (final item in driverHistory) {
                  try {
                    final lat = (item['lat'] as num).toDouble();
                    final lng = (item['lng'] as num).toDouble();
                    points.add(LatLng(lat, lng));
                  } catch (_) {}
                }
                if (points.isNotEmpty) {
                  setState(() {
                    _polylines = {
                      Polyline(
                        polylineId: const PolylineId('driver_history'),
                        color: AppColores.buttonPrimary,
                        width: 5,
                        points: points,
                      ),
                    };
                  });
                }
              }
            }
          } catch (e) {
            debugPrint('[RutaClienteDestino] Error procesando snapshot solicitud: $e');
          }
        });
      } catch (e) {
        debugPrint('[RutaClienteDestino] No se pudo subscribir a solicitud: $e');
      }
    });
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final conductorIcon = await MarkerIconHelper.fromAsset(
      'assets/img/taxi_icon.png',
      size: const Size(102, 102),
    );
    final destinoIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_red.png',
      size: const Size(108, 108),
    );
    if (!mounted) return;
    setState(() {
      _conductorMarkerIcon = conductorIcon;
      _destinoMarkerIcon = destinoIcon;
    });
  }

   Future<void> _actualizarRuta() async {
    if (!mounted || _isUpdatingRoute) return;
    _isUpdatingRoute = true;

    try {
      final vm = Provider.of<Rutaclientedestinoviewmodel>(
        context,
        listen: false,
      );
      final puntos = await vm.obtenerPolylineConductorDestino();
      final conductorLatLng =
          (vm.latConductor != null && vm.lngConductor != null)
          ? LatLng(vm.latConductor!, vm.lngConductor!)
          : null;
      final destinoLatLng = (vm.latDestino != null && vm.lngDestino != null)
          ? LatLng(vm.latDestino!, vm.lngDestino!)
          : null;

      if (!mounted) return;

      LatLng? nextLastConductor = _lastConductorLatLng;
      LatLng? nextConductorLatLng = _conductorLatLng;
      double nextConductorRotation = _conductorRotation;

      if (conductorLatLng != null) {
        if (nextLastConductor != null) {
          final movedMeters = _calculateDistance(
            nextLastConductor.latitude,
            nextLastConductor.longitude,
            conductorLatLng.latitude,
            conductorLatLng.longitude,
          );
          if (movedMeters >= 1.5) {
            final targetHeading = _bearingBetween(
              nextLastConductor,
              conductorLatLng,
            );
            nextConductorRotation = _lerpAngle(
              nextConductorRotation,
              targetHeading,
              0.45,
            );
          }
        } else if (destinoLatLng != null) {
          nextConductorRotation = _bearingBetween(
            conductorLatLng,
            destinoLatLng,
          );
        }

        nextLastConductor = conductorLatLng;
        nextConductorLatLng = conductorLatLng;
      }

      if (puntos.isEmpty) {
        setState(() {
          _polylines = {};
          _distancia = '';
          _conductorLatLng = nextConductorLatLng;
          _lastConductorLatLng = nextLastConductor;
          _conductorRotation = nextConductorRotation;
        });
        return;
      }

      final distanciaMetros = vm.calcularDistanciaPolyline(puntos);
      final distanciaStr = distanciaMetros >= 1000
          ? '${(distanciaMetros / 1000).toStringAsFixed(2)} km'
          : '${distanciaMetros.toStringAsFixed(0)} m';

      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('ruta'),
            color: AppColores.buttonPrimary,
            width: 6,
            points: puntos,
          ),
        };
        _distancia = distanciaStr;
        _conductorLatLng = nextConductorLatLng;
        _lastConductorLatLng = nextLastConductor;
        _conductorRotation = nextConductorRotation;
      });

      final segundos = await vm.calcularTiempoEstimado();
      if (segundos != null) {
        final minutos = (segundos / 60).ceil();
        vm.setTiempoEstimado('$minutos min');
      }

      await _fitConductorDestinoCamera(conductorLatLng, destinoLatLng);
    } finally {
      _isUpdatingRoute = false;
    }
  }

  LatLngBounds _buildBounds(LatLng a, LatLng b) {
    return LatLngBounds(
      southwest: LatLng(
        a.latitude < b.latitude ? a.latitude : b.latitude,
        a.longitude < b.longitude ? a.longitude : b.longitude,
      ),
      northeast: LatLng(
        a.latitude > b.latitude ? a.latitude : b.latitude,
        a.longitude > b.longitude ? a.longitude : b.longitude,
      ),
    );
  }

  LatLngBounds _buildExpandedBounds(
    LatLng a,
    LatLng b, {
    double expansionFactor = 0.2,
    double minDelta = 0.001,
  }) {
    final base = _buildBounds(a, b);
    final latDelta = (base.northeast.latitude - base.southwest.latitude).abs();
    final lngDelta = (base.northeast.longitude - base.southwest.longitude)
        .abs();

    final extraLat = Math.max(latDelta * expansionFactor, minDelta);
    final extraLng = Math.max(lngDelta * expansionFactor, minDelta);

    return LatLngBounds(
      southwest: LatLng(
        base.southwest.latitude - extraLat,
        base.southwest.longitude - extraLng,
      ),
      northeast: LatLng(
        base.northeast.latitude + extraLat,
        base.northeast.longitude + extraLng,
      ),
    );
  }

  double _cameraPaddingForDistance(double distanceMeters) {
    if (distanceMeters < 400) return 130;
    if (distanceMeters < 1500) return 110;
    if (distanceMeters < 5000) return 96;
    return 84;
  }

  double _normalizeAngle(double angle) {
    final normalized = angle % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final dy = to.latitude - from.latitude;
    final dx = to.longitude - from.longitude;
    return _normalizeAngle(Math.atan2(dx, dy) * 180 / Math.pi);
  }

  double _lerpAngle(double from, double to, double t) {
    final diff = ((to - from + 540) % 360) - 180;
    return _normalizeAngle(from + diff * t);
  }

  Future<void> _fitConductorDestinoCamera(
    LatLng? conductor,
    LatLng? destino,
  ) async {
    final controller = _mapController;
    if (controller == null || conductor == null || destino == null) return;

    final distanceMeters = _calculateDistance(
      conductor.latitude,
      conductor.longitude,
      destino.latitude,
      destino.longitude,
    );
    final bounds = _buildExpandedBounds(
      conductor,
      destino,
      minDelta: distanceMeters < 500 ? 0.0012 : 0.0008,
    );
    final center = LatLng(
      (conductor.latitude + destino.latitude) / 2,
      (conductor.longitude + destino.longitude) / 2,
    );
    final dy = destino.latitude - conductor.latitude;
    final dx = destino.longitude - conductor.longitude;
    final bearing = (Math.atan2(dx, dy) * 180 / Math.pi + 360) % 360;
    final targetZoom = _getZoomLevel(distanceMeters);

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          _cameraPaddingForDistance(distanceMeters),
        ),
      );
      final currentZoom = await controller.getZoomLevel();
      final regulatedZoom = currentZoom > targetZoom ? targetZoom : currentZoom;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: center, zoom: regulatedZoom, bearing: bearing),
        ),
      );
    } catch (_) {}
  }
// Detecta si el dispositivo tiene barra de navegación inferior (Android/iOS)
bool hasNavigationBar(BuildContext context) {
  return MediaQuery.of(context).padding.bottom > 0;
}
  // Calcula la distancia entre dos coordenadas en metros (Haversine)
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000; // Radio de la Tierra en metros
    final dLat = (lat2 - lat1) * Math.pi / 180;
    final dLon = (lon2 - lon1) * Math.pi / 180;
    final a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.pi / 180) *
            Math.cos(lat2 * Math.pi / 180) *
            Math.sin(dLon / 2) *
            Math.sin(dLon / 2);
    final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  // Devuelve un nivel de zoom adecuado según la distancia en metros
  double _getZoomLevel(double distanceMeters) {
    if (distanceMeters < 80) return 18.0;
    if (distanceMeters < 180) return 17.3;
    if (distanceMeters < 400) return 16.6;
    if (distanceMeters < 900) return 15.9;
    if (distanceMeters < 1800) return 15.2;
    if (distanceMeters < 3500) return 14.5;
    if (distanceMeters < 7000) return 13.8;
    if (distanceMeters < 13000) return 13.1;
    if (distanceMeters < 22000) return 12.4;
    return 11.8;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animacionMarcadorTimer?.cancel();
    _conductorLocationSub?.cancel();
    _conductorLocationFirestoreSub?.cancel();
    _mapController?.dispose();
    // Remover listener del ViewModel para evitar llamadas tras dispose
    if (_isRouteListenerAttached) {
      _viewModel?.removeListener(_actualizarRuta);
      _isRouteListenerAttached = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_rutaClienteDestinoOverlayStyle);
      // Al volver a la app, actualizar datos de la solicitud (ubicación del conductor, estado, etc.)
      final vm = Provider.of<Rutaclientedestinoviewmodel>(
        context,
        listen: false,
      );
      vm.cargarDatosConductorYUbicacionDestino(widget.idSolicitud);
    }
    // Puedes agregar lógica en onPause si lo necesitas
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _rutaClienteDestinoOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          body: Consumer<Rutaclientedestinoviewmodel>(
            builder: (context, vm, _) {
              return _buildMainContent(context, vm);
            },
          ),
        ),
      ),
    );
  }

  void _shareLocation(Rutaclientedestinoviewmodel vm) async {
    final conductorLatLng = _conductorLatLng ??
        ((vm.latConductor != null && vm.lngConductor != null)
            ? LatLng(vm.latConductor!, vm.lngConductor!)
            : null);
    if (conductorLatLng != null) {
      final url =
          'https://www.google.com/maps/search/?api=1&query=${conductorLatLng.latitude},${conductorLatLng.longitude}';
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Compartir ubicación',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map, color: Colors.white),
                    label: const Text('Google Maps', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.primary,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await launchUrl(Uri.parse(url));
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.chat, color: Colors.white),
                    label: const Text('WhatsApp', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final whatsappUrl =
                          'https://wa.me/?text=Ubicación%20del%20conductor:%20$url';
                      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                        await launchUrl(Uri.parse(whatsappUrl));
                      } else {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No se pudo abrir WhatsApp'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación no disponible aún'),
        ),
      );
    }
  }

  void _onHelpPressed(Rutaclientedestinoviewmodel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColores.primary,
                      backgroundImage: vm.fotoConductor.isNotEmpty
                          ? NetworkImage(vm.fotoConductor)
                          : null,
                      child: vm.fotoConductor.isEmpty
                          ? const Icon(Icons.person, size: 24, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        vm.nombreConductor.isNotEmpty ? vm.nombreConductor : 'Conductor',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColores.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Cuál es el estado de mi solicitud?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.black54),
                  onTap: () { Navigator.pop(ctx); },
                ),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cambiar mi dirección destino', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.black54),
                  onTap: () { Navigator.pop(ctx); },
                ),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Problemas con el conductor', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.black54),
                  onTap: () { Navigator.pop(ctx); },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onDetails(Rutaclientedestinoviewmodel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Detalles del Conductor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                CircleAvatar(
                  radius: 46,
                  backgroundColor: AppColores.primary.withValues(alpha: 0.1),
                  backgroundImage: vm.fotoConductor.isNotEmpty ? NetworkImage(vm.fotoConductor) : null,
                  child: vm.fotoConductor.isEmpty
                      ? const Icon(Icons.person, size: 40, color: AppColores.primary)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  vm.nombreConductor.isNotEmpty ? vm.nombreConductor : 'Conductor',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: vm.fotoVehiculo.isNotEmpty
                            ? Image.network(
                                vm.fotoVehiculo,
                                width: 80,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 80,
                                height: 60,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.local_taxi, color: Colors.grey),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vehículo asignado',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              vm.placaVehiculo.isNotEmpty ? vm.placaVehiculo : '---',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColores.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Main content extracted for clarity
  Widget _buildMainContent(BuildContext context, Rutaclientedestinoviewmodel vm) {
    LatLng? destinoLatLng = (vm.latDestino != null && vm.lngDestino != null)
        ? LatLng(vm.latDestino!, vm.lngDestino!)
        : null;
    LatLng? conductorLatLng = _conductorLatLng ??
        ((vm.latConductor != null && vm.lngConductor != null)
            ? LatLng(vm.latConductor!, vm.lngConductor!)
            : null);
    final markers = <Marker>{
      if (conductorLatLng != null)
        Marker(
          markerId: const MarkerId('conductor'),
          position: conductorLatLng,
          rotation: _conductorRotation,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: 'Conductor'),
          icon: _conductorMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      if (destinoLatLng != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destinoLatLng,
          infoWindow: const InfoWindow(title: 'Destino'),
          icon: _destinoMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom > 0 ? mq.padding.bottom : 20.0;

    return Stack(
      children: [
        // Mapa
        Positioned.fill(
          child: _MapWidget(
            markers: markers,
            conductorLatLng: conductorLatLng,
            destinoLatLng: destinoLatLng,
            mapControllerSetter: (controller) => _mapController = controller,
            polylines: _polylines,
          ),
        ),
        
        // Controles Inferiores (Botón de Enfoque)
        Positioned(
          right: 16,
          bottom: safeBottom + 16,
          child: FloatingActionButton(
            backgroundColor: AppColores.primary,
            child: Icon(
              _mostrarSoloDestino ? Icons.flag : Icons.person_pin_circle,
              color: Colors.white,
            ),
            onPressed: () async {
              setState(() {
                _mostrarSoloDestino = !_mostrarSoloDestino;
              });
              if (_mapController == null) return;
              if (_mostrarSoloDestino && destinoLatLng != null) {
                await _mapController!.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: destinoLatLng, zoom: 15.8, tilt: 0),
                  ),
                );
                return;
              }
              await _fitConductorDestinoCamera(conductorLatLng, destinoLatLng);
            },
          ),
        ),
        
        // Tarjeta Superior Flotante
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: UserTripInfoCard(
            title: 'En camino al destino',
            name: vm.nombreConductor,
            vehiclePlate: vm.placaVehiculo,
            userPhotoUrl: vm.fotoConductor,
            vehiclePhotoUrl: vm.fotoVehiculo,
            unreadCount: 0,
            isCancelling: false,
            cancelEnabled: false,
            primaryActionText: 'Ubicación',
            primaryActionIcon: Icons.my_location,
            onPrimaryAction: () => _shareLocation(vm),
            onCancel: () {},
            etaText: vm.tiempoEstimado.isNotEmpty ? vm.tiempoEstimado : '--',
            distanceText: _distancia.isNotEmpty ? _distancia : '--',
            onHelp: () => _onHelpPressed(vm),
            onDetails: () => _onDetails(vm),
          ),
        ),
      ],
    );
  }
}

class _MapWidget extends StatelessWidget {
  final Set<Marker> markers;
  final LatLng? conductorLatLng;
  final LatLng? destinoLatLng;
  final Function(GoogleMapController) mapControllerSetter;
  final Set<Polyline> polylines;
  const _MapWidget({
    required this.markers,
    required this.conductorLatLng,
    required this.destinoLatLng,
    required this.mapControllerSetter,
    required this.polylines,
  });

  @override
  Widget build(BuildContext context) {
    LatLng initialTarget;
    if (conductorLatLng != null && destinoLatLng != null) {
      initialTarget = LatLng(
        (conductorLatLng!.latitude + destinoLatLng!.latitude) / 2,
        (conductorLatLng!.longitude + destinoLatLng!.longitude) / 2,
      );
    } else {
      initialTarget =
          conductorLatLng ??
          destinoLatLng ??
          const LatLng(8.2595534, -73.353469);
    }
    return Stack(
      children: [
        Mapagoogle(
          initialTarget: initialTarget,
          initialZoom: 15.0,
          markers: markers,
          polylines: polylines,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) {
            mapControllerSetter(controller);
          },
        ),
      ],
    );
  }
}
