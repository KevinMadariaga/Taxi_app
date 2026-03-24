import 'dart:async';
import 'dart:math' as Math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/features/trip_tracking_cliente/viewmodels/trip_route_tracking_viewmodel.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_route_tracking_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/widgets/LoaderCancelado.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/widgets/universal_chat_widget.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';

enum _EnCaminoModalResult { continuar, timeoutSinRespuesta }

class RutaCliente extends StatefulWidget {
  final String idSolicitud;
  const RutaCliente({Key? key, required this.idSolicitud}) : super(key: key);

  @override
  State<RutaCliente> createState() => _RutaClienteState();
}

class _RutaClienteState extends State<RutaCliente> with WidgetsBindingObserver {
  static const SystemUiOverlayStyle _rutaClienteOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      );

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
    if (distanceMeters < 200) return 18.0;
    if (distanceMeters < 500) return 17.0;
    if (distanceMeters < 1000) return 16.0;
    if (distanceMeters < 2000) return 15.0;
    if (distanceMeters < 5000) return 14.0;
    if (distanceMeters < 10000) return 13.0;
    if (distanceMeters < 20000) return 12.0;
    return 11.0;
  }

  String? _tiempoEstimadoTexto;
  LatLng? _conductorLatLng;
  double? _distanciaMetros;
  List<LatLng> _polyline = [];
  StreamSubscription<String?>? _estadoSolicitudSub;
  Timer? _animacionMarcadorTimer;
  GoogleMapController? _mapController;
  late final Rutaclienteviewmodel _vm;
  VoidCallback? _vmListener;
  bool _isMapUpdateInProgress = false;
  LatLng? _lastCameraClienteLatLng;
  LatLng? _lastCameraConductorLatLng;
  bool _mostrarSoloCliente = false;
  BitmapDescriptor? _conductorMarkerIcon;
  BitmapDescriptor? _clienteMarkerIcon;
  bool _enCaminoModalVisible = false;
  bool _enCaminoFlowHandled = false;
  bool _clienteConfirmoVoyEnCamino = false;
  bool _cancelNavigationHandled = false;
  bool _completionNavigationHandled = false;

  bool _sameLatLng(LatLng? a, LatLng? b, {double epsilon = 0.000001}) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a.latitude - b.latitude).abs() < epsilon &&
        (a.longitude - b.longitude).abs() < epsilon;
  }

  bool _didCameraPairChange(LatLng cliente, LatLng conductor) {
    return !_sameLatLng(_lastCameraClienteLatLng, cliente) ||
        !_sameLatLng(_lastCameraConductorLatLng, conductor);
  }

  Future<void> _onVmChanged() async {
    if (!mounted) return;

    final conductorLatLng =
        (_vm.latConductor != null && _vm.lngConductor != null)
        ? LatLng(_vm.latConductor!, _vm.lngConductor!)
        : null;

    final clienteLatLng = (_vm.latCliente != null && _vm.lngCliente != null)
        ? LatLng(_vm.latCliente!, _vm.lngCliente!)
        : null;

    if (!_sameLatLng(_conductorLatLng, conductorLatLng)) {
      setState(() {
        _conductorLatLng = conductorLatLng;
      });
    }

    if (_mapController == null ||
        conductorLatLng == null ||
        clienteLatLng == null) {
      return;
    }

    // Ignora notifyListeners de otras áreas (por ejemplo chat) si las coordenadas no cambiaron.
    if (!_didCameraPairChange(clienteLatLng, conductorLatLng)) {
      return;
    }

    if (_isMapUpdateInProgress) return;
    _isMapUpdateInProgress = true;

    try {
      final polyline = await _vm.obtenerPolylineClienteConductor();

      double? distancia;
      String tiempoTexto = '-';

      if (polyline.isNotEmpty) {
        distancia = _vm.calcularDistanciaPolyline(polyline);
        final tiempo = await _vm.calcularTiempoEstimado();
        if (tiempo != null && tiempo != -1) {
          tiempoTexto = '${(tiempo / 60).ceil()} min';
        }
      }

      if (!mounted) return;

      setState(() {
        _polyline = polyline;
        _distanciaMetros = distancia;
        _tiempoEstimadoTexto = tiempoTexto;
      });

      final centerLat = (clienteLatLng.latitude + conductorLatLng.latitude) / 2;
      final centerLng =
          (clienteLatLng.longitude + conductorLatLng.longitude) / 2;
      final dy = conductorLatLng.latitude - clienteLatLng.latitude;
      final dx = conductorLatLng.longitude - clienteLatLng.longitude;
      final bearing = (Math.atan2(dx, dy) * 180 / Math.pi + 360) % 360;
      final distanceMeters = _calculateDistance(
        clienteLatLng.latitude,
        clienteLatLng.longitude,
        conductorLatLng.latitude,
        conductorLatLng.longitude,
      );
      final zoom = _getZoomLevel(distanceMeters);

      if (!mounted || _mapController == null) return;

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(centerLat, centerLng),
            zoom: zoom,
            bearing: bearing,
          ),
        ),
      );

      _lastCameraClienteLatLng = clienteLatLng;
      _lastCameraConductorLatLng = conductorLatLng;
    } finally {
      _isMapUpdateInProgress = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_rutaClienteOverlayStyle);
    _vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _vm.inicializarNotificaciones();
      await _vm.mostrarNotificacion(
        'Conductor asignado',
        'Vendrá pronto a recogerte.',
      );
      await _vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
      await _cargarMarcadoresPersonalizados();
      _vm.iniciarChat(widget.idSolicitud);
      // Escuchar estado de la solicitud
      _estadoSolicitudSub = _vm
          .escucharEstadoSolicitudStream(widget.idSolicitud)
          .listen((estado) async {
            await _manejarCambioEstadoSolicitud(estado);
          });
      // Escuchar ubicación del conductor desde el ViewModel
      _vm.escucharUbicacionConductor(widget.idSolicitud);
      _vmListener ??= () {
        _onVmChanged();
      };
      _vm.addListener(_vmListener!);
      await _onVmChanged();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animacionMarcadorTimer?.cancel();
    _estadoSolicitudSub?.cancel();
    if (_vmListener != null) {
      _vm.removeListener(_vmListener!);
    }
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_rutaClienteOverlayStyle);
      // Al volver a la app, solo actualizar la posición del marcador del conductor
      _vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
      // Si hay nueva ubicación, solo mover el marcador
      LatLng? nuevaLatLng =
          (_vm.latConductor != null && _vm.lngConductor != null)
          ? LatLng(_vm.latConductor!, _vm.lngConductor!)
          : null;
      if (nuevaLatLng != null) {
        setState(() {
          _conductorLatLng = nuevaLatLng;
        });
      }
      _onVmChanged();
    }
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final conductorIcon = await MarkerIconHelper.fromAsset(
      'assets/img/taxi_icon.png',
      size: const Size(108, 108),
    );
    final clienteIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_blue.png',
      size: const Size(102, 102),
    );
    if (!mounted) return;
    setState(() {
      _conductorMarkerIcon = conductorIcon;
      _clienteMarkerIcon = clienteIcon;
    });
  }

  Future<void> _manejarCambioEstadoSolicitud(String? estadoRaw) async {
    if (!mounted || estadoRaw == null) return;

    final estado = estadoRaw.trim().toLowerCase();
    final estadoCompacto = estado.replaceAll('_', ' ').replaceAll('-', ' ');
    final esCancelado = estado == 'cancelado' || estado == 'cancelada';
    if (esCancelado) {
      if (_cancelNavigationHandled) return;
      _cancelNavigationHandled = true;

      _estadoSolicitudSub?.cancel();
      _estadoSolicitudSub = null;

      if (_enCaminoModalVisible && mounted) {
        Navigator.of(context).pop();
        _enCaminoModalVisible = false;
      }

      await _vm.limpiarSolicitudActiva();
      if (!mounted) return;

      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const InicioClienteView(),
        delay: const Duration(milliseconds: 1200),
        title: 'Solicitud cancelada',
        subtitle: 'Regresando al inicio...',
        icon: Icons.cancel_rounded,
        clearStackOnNext: true,
      );
      return;
    }

    final esCompletado =
        estadoCompacto.contains('completad') ||
        estadoCompacto.contains('completed') ||
        estadoCompacto.contains('finaliz');
    if (esCompletado) {
      if (_completionNavigationHandled) return;
      _completionNavigationHandled = true;

      _estadoSolicitudSub?.cancel();
      _estadoSolicitudSub = null;

      if (_enCaminoModalVisible && mounted) {
        Navigator.of(context).pop();
        _enCaminoModalVisible = false;
      }

      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => ResumenClienteView(solicitudId: widget.idSolicitud),
        delay: const Duration(milliseconds: 1200),
        title: 'Viaje completado',
        subtitle: 'Preparando resumen del viaje...',
        clearStackOnNext: true,
      );
      return;
    }

    final esEnRuta =
        estado == 'en ruta' ||
        estado == 'en_ruta' ||
        estado == 'enruta' ||
        estado == 'en progreso' ||
        estado == 'en_progreso';

    if (esEnRuta) {
      if (_enCaminoFlowHandled) return;
      _enCaminoFlowHandled = true;
      //_navegarARutaClienteDestino();
      return;
    }

    final mostrarModalConfirmacion =
        estado == 'en camino' ||
        estado == 'encamino' ||
        estado == 'en espera' ||
        estado == 'en_espera' ||
        estado == 'enespera';

    // En estados intermedios no navega automáticamente: primero muestra la modal.
    if (mostrarModalConfirmacion && !_clienteConfirmoVoyEnCamino) {
      await _mostrarModalEnCamino();
    }
  }

  Future<void> _mostrarModalEnCamino() async {
    if (!mounted || _enCaminoFlowHandled || _enCaminoModalVisible) return;

    _enCaminoModalVisible = true;
    final resultado = await showModalBottomSheet<_EnCaminoModalResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: _EnCaminoCountdownSheet(idSolicitud: widget.idSolicitud),
        );
      },
    );

    _enCaminoModalVisible = false;
    if (!mounted || _enCaminoFlowHandled) return;

    if (resultado == _EnCaminoModalResult.continuar) {
      // Al confirmar "Voy en camino" se mantiene en esta vista.
      _clienteConfirmoVoyEnCamino = true;
      return;
    }

    if (resultado == _EnCaminoModalResult.timeoutSinRespuesta) {
      _enCaminoFlowHandled = true;
      await _manejarSinRespuestaPorTimeout();
    }
  }

  Future<void> _manejarSinRespuestaPorTimeout() async {
    _estadoSolicitudSub?.cancel();
    _estadoSolicitudSub = null;

    var loaderVisible = false;
    if (mounted) {
      loaderVisible = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoaderSolicitudCancelada(
          texto: 'Tiempo agotado.\nCancelando solicitud...',
        ),
      );
    }

    try {
      await _vm.cancelarSolicitudSinRespuesta(widget.idSolicitud);
      await _vm.limpiarSolicitudActiva();
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      debugPrint('Error al cancelar por timeout: $e');
    } finally {
      if (loaderVisible && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const InicioClienteView()),
      (route) => false,
    );
  }

  // void _navegarARutaClienteDestino() {
  //   if (!mounted) return;
  //   navigateWithIntermediateLoader(
  //     context: context,
  //     nextBuilder: (context) => TripRouteTrackingScreen(
  //       solicitudId: widget.idSolicitud,
  //       currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
  //       tipoUsuario: TipoUsuarioTracking.cliente,
  //     ),
  //     title: 'Ruta confirmada',
  //     subtitle: 'Preparando el viaje al destino...',
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    LatLng? clienteLatLng;
    LatLng? conductorLatLng;
    final vm = Provider.of<Rutaclienteviewmodel>(context);
    clienteLatLng = (vm.latCliente != null && vm.lngCliente != null)
        ? LatLng(vm.latCliente!, vm.lngCliente!)
        : null;
    conductorLatLng =
        _conductorLatLng ??
        ((vm.latConductor != null && vm.lngConductor != null)
            ? LatLng(vm.latConductor!, vm.lngConductor!)
            : null);
    final markers = <Marker>{
      if (_mostrarSoloCliente && clienteLatLng != null)
        Marker(
          markerId: const MarkerId('cliente'),
          position: clienteLatLng,
          infoWindow: const InfoWindow(title: 'Cliente'),
          icon:
              _clienteMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      if (!_mostrarSoloCliente && conductorLatLng != null)
        Marker(
          markerId: const MarkerId('conductor'),
          position: conductorLatLng,
          infoWindow: const InfoWindow(title: 'Conductor'),
          icon:
              _conductorMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      if (!_mostrarSoloCliente && clienteLatLng != null)
        Marker(
          markerId: const MarkerId('cliente'),
          position: clienteLatLng,
          infoWindow: const InfoWindow(title: 'Cliente'),
          icon:
              _clienteMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
    };

    // --- NUEVO RETURN PRINCIPAL ---
    return WillPopScope(
      onWillPop: () async => false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _rutaClienteOverlayStyle,
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              // El mapa respeta la zona superior (notch/status bar) en iPhone.
              Expanded(
                child: Stack(
                  children: [
                    Mapagoogle(
                      initialTarget:
                          conductorLatLng ??
                          clienteLatLng ??
                          const LatLng(8.2595534, -73.353469),
                      initialZoom: 15.0,
                      markers: markers,
                      polylines: _polyline.isNotEmpty
                          ? {
                              Polyline(
                                polylineId: const PolylineId('ruta'),
                                points: _polyline,
                                color: AppColores.buttonPrimary,
                                width: 5,
                              ),
                            }
                          : {},
                      circles: {},
                      onMapCreated: (controller) => _mapController = controller,
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
                    if (_tiempoEstimadoTexto != null ||
                        _distanciaMetros != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_tiempoEstimadoTexto != null) ...[
                                  const Icon(
                                    Icons.timer,
                                    color: AppColores.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$_tiempoEstimadoTexto',
                                    style: const TextStyle(
                                      color: AppColores.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                                if (_distanciaMetros != null) ...[
                                  if (_tiempoEstimadoTexto != null)
                                    const SizedBox(width: 16),
                                  const Icon(
                                    Icons.route,
                                    color: AppColores.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(_distanciaMetros! / 1000).toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      color: AppColores.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Panel inferior anclado al borde inferior, respetando home indicator.
              Container(
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
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
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
          ),
        ),
      ),
    );
  }

  // Mosstrar información del conductor y vehículo en un card debajo del mapa
  Widget _infoRow() {
    final vm = Provider.of<Rutaclienteviewmodel>(context);
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
                // Mostrar foto del vehículo y debajo la placa
                if (vm.fotoVehiculo.isNotEmpty || vm.placaVehiculo.isNotEmpty)
                  Column(
                    children: [
                      if (vm.fotoVehiculo.isNotEmpty)
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

  // Botones de chat y cancelar
  Widget _bottomButtons() {
    final vm = Provider.of<Rutaclienteviewmodel>(context);
    int mensajesPendientes = vm.mensajesPendientes;
    final double screenW = MediaQuery.of(context).size.width;
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
            child: ChatButton(
              mensajesPendientes: mensajesPendientes,
              buttonIconSize: buttonIconSize,
              buttonFontSize: buttonFontSize,
              spacing: spacing,
              isTablet: isTablet,
              solicitudId: widget.idSolicitud,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: CancelButton(
              buttonIconSize: buttonIconSize,
              buttonFontSize: buttonFontSize,
              buttonBorderRadius: buttonBorderRadius,
              paddingV: paddingV,
              solicitudId: widget.idSolicitud,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnCaminoCountdownSheet extends StatefulWidget {
  final String idSolicitud;

  const _EnCaminoCountdownSheet({required this.idSolicitud});

  @override
  State<_EnCaminoCountdownSheet> createState() =>
      _EnCaminoCountdownSheetState();
}

class _EnCaminoCountdownSheetState extends State<_EnCaminoCountdownSheet> {
  static const int _duracionTotalSegundos = 180;
  int _segundosRestantes = _duracionTotalSegundos;
  Timer? _timer;
  bool _timeoutTriggered = false;
  bool _updatingEstado = false;

  void _cerrarPorTimeout() {
    if (_timeoutTriggered || !mounted) return;
    _timeoutTriggered = true;
    _timer?.cancel();
    Navigator.of(context).pop(_EnCaminoModalResult.timeoutSinRespuesta);
  }

  Future<void> _marcarVoyEnCamino() async {
    if (_updatingEstado || !mounted) return;

    setState(() {
      _updatingEstado = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.idSolicitud)
          .update({'estado': 'en camino'});

      if (!mounted) return;
      Navigator.of(context).pop(_EnCaminoModalResult.continuar);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updatingEstado = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo confirmar el estado.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes <= 1) {
        setState(() {
          _segundosRestantes = 0;
        });
        _cerrarPorTimeout();
        return;
      }
      setState(() {
        _segundosRestantes -= 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatearTiempo(int totalSegundos) {
    final minutos = (totalSegundos ~/ 60).toString().padLeft(2, '0');
    final segundos = (totalSegundos % 60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, topPadding > 0 ? 16 : 28, 24, 32),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.directions_car_filled_rounded,
                color: AppColores.primary,
                size: 72,
              ),
              const SizedBox(height: 20),
              const Text(
                'El conductor esta en tu ubicacion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tiempo de espera de confirmacion',
                style: TextStyle(fontSize: 16, color: AppColores.textPrimary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: AppColores.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _formatearTiempo(_segundosRestantes),
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: AppColores.primary,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _updatingEstado ? null : _marcarVoyEnCamino,
                  child: _updatingEstado
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Voy en camino',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatButton extends StatefulWidget {
  final int mensajesPendientes;
  final double buttonIconSize;
  final double buttonFontSize;
  final double spacing;
  final bool isTablet;
  final String solicitudId;
  const ChatButton({
    required this.mensajesPendientes,
    required this.buttonIconSize,
    required this.buttonFontSize,
    required this.spacing,
    required this.isTablet,
    required this.solicitudId,
  });

  @override
  State<ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends State<ChatButton> {
  bool chatAbierto = false;
  bool dialogMostrado = false;

  Future<void> limpiarMensajesPendientes(BuildContext context) async {
    final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
    final usuarioId = vm.usuarioId;
    if (usuarioId == null) return;

    final pendientes = vm.mensajes
        .where(
          (m) => m.senderId != usuarioId && !(m.readBy[usuarioId] ?? false),
        )
        .toList();

    if (pendientes.isEmpty) return;

    await Future.wait(
      pendientes.map(
        (m) => vm.chatService
            .markMessageRead(
              solicitudId: widget.solicitudId,
              messageId: m.id,
              userId: usuarioId,
            )
            .catchError((_) {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: widget.isTablet
              ? 70
              : widget.spacing < 8
              ? 40
              : 56,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColores.primary, width: 2.5),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              if (chatAbierto || dialogMostrado) return;
              setState(() {
                chatAbierto = true;
                dialogMostrado = true;
              });
              limpiarMensajesPendientes(context);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (sheetContext) {
                  return SizedBox(
                    height: MediaQuery.of(sheetContext).size.height * 0.9,
                    child: UniversalChatWidget(
                      solicitudId: widget.solicitudId,
                      chatTitle: 'Chat con el conductor',
                      backgroundColor: Colors.white,
                      myMessageColor: AppColores.primary,
                      otherMessageColor: Colors.grey.shade200,
                      sendButtonColor: AppColores.primary,
                      autoFocus: true,
                    ),
                  );
                },
              ).then((_) {
                if (!mounted) return;
                setState(() {
                  chatAbierto = false;
                  dialogMostrado = false;
                });
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat,
                  color: AppColores.primary,
                  size: widget.buttonIconSize,
                ),
                SizedBox(width: widget.spacing / 2),
                Text(
                  'Chat',
                  style: TextStyle(
                    color: AppColores.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: widget.buttonFontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.mensajesPendientes > 0)
          Positioned(
            right: 0,
            top: widget.isTablet
                ? -12
                : widget.spacing < 8
                ? -4
                : -8,
            child: Container(
              padding: EdgeInsets.all(
                widget.isTablet
                    ? 10
                    : widget.spacing < 8
                    ? 3
                    : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: widget.isTablet ? 3 : 2,
                ),
              ),
              constraints: BoxConstraints(
                minWidth: widget.isTablet
                    ? 36
                    : widget.spacing < 8
                    ? 14
                    : 24,
                minHeight: widget.isTablet
                    ? 36
                    : widget.spacing < 8
                    ? 14
                    : 24,
              ),
              child: Center(
                child: Text(
                  widget.mensajesPendientes.toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: widget.isTablet
                        ? 22
                        : widget.spacing < 8
                        ? 8
                        : 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CancelButton extends StatelessWidget {
  final double buttonIconSize;
  final double buttonFontSize;
  final double buttonBorderRadius;
  final double paddingV;
  final String solicitudId;
  const CancelButton({
    required this.buttonIconSize,
    required this.buttonFontSize,
    required this.buttonBorderRadius,
    required this.paddingV,
    required this.solicitudId,
  });

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<Rutaclienteviewmodel>(context);
    return ElevatedButton.icon(
      icon: Icon(Icons.cancel, color: Colors.white, size: buttonIconSize),
      label: Text(
        'Cancelar',
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
        await vm.cancelarSolicitud(solicitudId);
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LoaderSolicitudCancelada(),
        );
        await Future.delayed(const Duration(seconds: 2));
        // Eliminar la solicitud de Firestore
        try {
          await FirebaseFirestore.instance
              .collection('solicitudes')
              .doc(solicitudId)
              .delete();
        } catch (e) {
          debugPrint('Error eliminando solicitud cancelada: $e');
        }
        await Future.delayed(const Duration(seconds: 1));
        if (!context.mounted) return;
        Navigator.of(context).pop(); // Cierra el loader
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => InicioClienteView()),
          (route) => false,
        );
      },
    );
  }
}
