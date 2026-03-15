import 'dart:async';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class RutaClienteDestino extends StatefulWidget {
  final String idSolicitud;
  const RutaClienteDestino({Key? key, required this.idSolicitud})
    : super(key: key);

  @override
  State<RutaClienteDestino> createState() => _RutaClienteDestinoState();
}

class _RutaClienteDestinoState extends State<RutaClienteDestino>
    with WidgetsBindingObserver {
  static const SystemUiOverlayStyle _rutaClienteDestinoOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.white,
        systemNavigationBarContrastEnforced: false,
      );

  LatLng? _conductorLatLng;
  StreamSubscription<LatLng?>? _conductorLocationSub;
  StreamSubscription? _conductorLocationFirestoreSub;
  Timer? _animacionMarcadorTimer;
  GoogleMapController? _mapController;

  Set<Polyline> _polylines = {};
  String _distancia = '';

  Rutaclientedestinoviewmodel? _viewModel;
  bool _mostrarSoloDestino = false;
  bool _isUpdatingRoute = false;
  bool _isRouteListenerAttached = false;
  BitmapDescriptor? _conductorMarkerIcon;
  BitmapDescriptor? _destinoMarkerIcon;
  LatLng? _lastConductorLatLng;
  double _conductorRotation = 0;

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
      _viewModel!.inicializarNotificaciones();
      await _viewModel!.mostrarNotificacion(
        'Conductor en marcha',
        'Conductor está en camino al destino. ¡Prepárate para tu viaje!',
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
              final size = MediaQuery.of(context).size;
              final double screenW = size.width;
              final bool isTablet = screenW >= 1000;
              LatLng? destinoLatLng =
                  (vm.latDestino != null && vm.lngDestino != null)
                  ? LatLng(vm.latDestino!, vm.lngDestino!)
                  : null;
              LatLng? conductorLatLng =
                  _conductorLatLng ??
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
                    icon:
                        _conductorMarkerIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                  ),
                if (destinoLatLng != null)
                  Marker(
                    markerId: const MarkerId('destino'),
                    position: destinoLatLng,
                    infoWindow: const InfoWindow(title: 'Destino'),
                    icon:
                        _destinoMarkerIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                  ),
              };
              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        _MapWidget(
                          markers: markers,
                          conductorLatLng: conductorLatLng,
                          destinoLatLng: destinoLatLng,
                          mapControllerSetter: (controller) =>
                              _mapController = controller,
                          polylines: _polylines,
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: MediaQuery.of(context).padding.top + 28,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.28),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.white,
                              child: Container(
                                width: 260,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      color: AppColores.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      vm.tiempoEstimado,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppColores.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.route,
                                      color: AppColores.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _distancia,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: AppColores.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: SafeArea(
                            top: false,
                            child: FloatingActionButton(
                              backgroundColor: AppColores.primary,
                              child: Icon(
                                _mostrarSoloDestino
                                    ? Icons.flag
                                    : Icons.person_pin_circle,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                setState(() {
                                  _mostrarSoloDestino = !_mostrarSoloDestino;
                                });

                                if (_mapController == null) return;

                                if (_mostrarSoloDestino &&
                                    destinoLatLng != null) {
                                  await _mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: destinoLatLng,
                                        zoom: 15.8,
                                        tilt: 0,
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                await _fitConductorDestinoCamera(
                                  conductorLatLng,
                                  destinoLatLng,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isTablet ? 24 : 16),
                            topRight: Radius.circular(isTablet ? 24 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 24 : 12,
                            vertical: isTablet ? 24 : 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _infoRow(),
                              SizedBox(height: isTablet ? 12 : 8),
                              _bottomButtons(),
                            ],
                          ),
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
  }

  // Mosstrar información del conductor y vehículo en un card debajo del mapa
  Widget _infoRow() {
    final vm = Provider.of<Rutaclientedestinoviewmodel>(context);
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double paddingH = isTablet
        ? 32
        : screenW < 350
        ? 6
        : 12;
    final double paddingV = isTablet
        ? 24
        : screenW < 350
        ? 4
        : 8;
    final double avatarRadius = isTablet
        ? 60
        : screenW < 350
        ? 22
        : 40;
    final double spacing = isTablet
        ? 24
        : screenW < 350
        ? 6
        : 12;
    final double nameFontSize = isTablet
        ? 32
        : screenW < 350
        ? 12
        : 18;
    final double placaFontSize = isTablet
        ? 22
        : screenW < 350
        ? 10
        : 15;
    final double imageW = isTablet
        ? 160
        : screenW < 350
        ? 60
        : 100;
    final double imageH = isTablet
        ? 120
        : screenW < 350
        ? 40
        : 70;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(
          isTablet
              ? 24
              : screenW < 350
              ? 8
              : 12,
        ),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: spacing / 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(
                        isTablet
                            ? 12
                            : screenW < 350
                            ? 2
                            : 6,
                      ),
                      child: CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor: AppColores.primary,
                        backgroundImage: vm.fotoConductor.isNotEmpty
                            ? NetworkImage(vm.fotoConductor)
                            : null,
                        child: vm.fotoConductor.isEmpty
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                    ),
                    SizedBox(height: spacing / 2),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 16 : 8,
                        vertical: isTablet ? 6 : 2,
                      ),
                      child: Text(
                        vm.nombreConductor.isNotEmpty
                            ? vm.nombreConductor
                            : 'Conductor',
                        style: TextStyle(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: isTablet
                      ? 48
                      : screenW < 350
                      ? 8
                      : size.width * 0.12,
                ),
                if (vm.fotoVehiculo.isNotEmpty)
                  Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(
                          isTablet
                              ? 10
                              : screenW < 350
                              ? 2
                              : 5,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            isTablet
                                ? 18
                                : screenW < 350
                                ? 6
                                : 12,
                          ),
                          child: Image.network(
                            vm.fotoVehiculo,
                            width: imageW,
                            height: imageH,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      SizedBox(height: spacing / 2),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 16 : 8,
                          vertical: isTablet ? 6 : 2,
                        ),
                        child: Text(
                          vm.placaVehiculo.isNotEmpty
                              ? vm.placaVehiculo
                              : 'Placa no disponible',
                          style: TextStyle(
                            fontSize: placaFontSize,
                            color: AppColores.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomButtons() {
    final vm = Provider.of<Rutaclientedestinoviewmodel>(context);
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double paddingH = isTablet
        ? 32
        : screenW < 350
        ? 6
        : 16;
    final double paddingV = isTablet
        ? 24
        : screenW < 350
        ? 4
        : 8;
    final double buttonFontSize = isTablet
        ? 22
        : screenW < 350
        ? 13
        : 18;
    final double buttonIconSize = isTablet
        ? 32
        : screenW < 350
        ? 18
        : 24;
    final double buttonBorderRadius = isTablet
        ? 24
        : screenW < 350
        ? 8
        : 12;
    final double spacing = isTablet
        ? 24
        : screenW < 350
        ? 6
        : 16;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(buttonBorderRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(
                Icons.my_location,
                color: Colors.white,
                size: buttonIconSize,
              ),
              label: Text(
                'Ubicación',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: buttonFontSize,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.primary,
                padding: EdgeInsets.symmetric(vertical: paddingV * 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(buttonBorderRadius),
                ),
              ),
              onPressed: () async {
                final conductorLatLng =
                    _conductorLatLng ??
                    ((vm.latConductor != null && vm.lngConductor != null)
                        ? LatLng(vm.latConductor!, vm.lngConductor!)
                        : null);
                if (conductorLatLng != null) {
                  final url =
                      'https://www.google.com/maps/search/?api=1&query=${conductorLatLng.latitude},${conductorLatLng.longitude}';
                  await Clipboard.setData(ClipboardData(text: url));
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    builder: (context) {
                      return Container(
                        height: MediaQuery.of(context).size.height * 0.5,
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Compartir ubicación',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 32),
                            ElevatedButton.icon(
                              icon: Icon(Icons.map, color: Colors.white),
                              label: Text('Google Maps'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.primary,
                                minimumSize: Size(double.infinity, 48),
                              ),
                              onPressed: () async {
                                await launchUrl(Uri.parse(url));
                              },
                            ),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: Icon(Icons.chat, color: Colors.white),
                              label: Text('WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                minimumSize: Size(double.infinity, 48),
                              ),
                              onPressed: () async {
                                final whatsappUrl =
                                    'https://wa.me/?text=Ubicación%20del%20conductor:%20$url';
                                if (await canLaunchUrl(
                                  Uri.parse(whatsappUrl),
                                )) {
                                  await launchUrl(Uri.parse(whatsappUrl));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'No se pudo abrir WhatsApp',
                                      ),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ubicación no disponible'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.info, color: Colors.white, size: buttonIconSize),
              label: Text(
                'Estado',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: buttonFontSize,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.primary,
                padding: EdgeInsets.symmetric(vertical: paddingV * 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(buttonBorderRadius),
                ),
              ),
              onPressed: () {
                final estado = vm.estado;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Estado actual: $estado')),
                );
              },
            ),
          ),
        ],
      ),
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
