import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaDestinoView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaDestinoViewModel.dart';
import 'package:taxi_app/services/DireccionesServicio.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/utils/Mapa.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaConductorViewModel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/widgets/universal_chat_widget.dart';

class RutaConductor extends StatefulWidget {
  final String idSolicitud;

  const RutaConductor({super.key, required this.idSolicitud});

  @override
  State<RutaConductor> createState() => _RutaConductorState();
}

class _RutaConductorState extends State<RutaConductor>
    with WidgetsBindingObserver {
  static const SystemUiOverlayStyle _rutaConductorOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.white,
        systemNavigationBarContrastEnforced: false,
      );

  // Verifica conexión a internet
  Future<bool> _tieneConexionInternet() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity != ConnectivityResult.none;
    } catch (e) {
      debugPrint('[LOG] Error verificando conexión: $e');
      return false;
    }
  }

  // Detiene el tracking de ubicación en segundo plano
  Future<void> detenerTrackingBackground() async {
    try {
      debugPrint('[LOG] Deteniendo tracking background (al volver a la clase)');
      FlutterBackgroundService().invoke('stop');
    } catch (e) {
      debugPrint('Error deteniendo tracking background: $e');
    }
  }

  bool _chatModalAbierto = false;
  bool _yaLleguePressed = false;
  DateTime? _fechaUbicacionObtenida;
  Future<void> aceptarViaje() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  GoogleMapController? _mapController;

  LatLng? _ubicacionConductor;
  bool _loadingUbicacion = true;

  double _bearing = 0;

  StreamSubscription<Position>? _positionStream;

  bool _centraSoloConductor = true;

  final LatLng _initialTarget = LatLng(8.2595534, -73.353469);
  final double _initialZoom = 15.0;

  final Set<Circle> _circles = {};

  List<LatLng> _polylinePoints = [];
  bool _loadingPolyline = false;
  BitmapDescriptor? _clienteMarkerIcon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_rutaConductorOverlayStyle);
    RutaConductorViewModel.inicializarNotificaciones();
    // Al ingresar a la clase, detener tracking background si estaba activo
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[LOG] Volviendo a la clase RutaConductor');
      await detenerTrackingBackground();
      // No iniciar tracking background ni aceptarViaje aquí
      final vm = Provider.of<RutaConductorViewModel>(context, listen: false);
      final primeraVez = await vm.esPrimeraVezClase(widget.idSolicitud);
      if (primeraVez) {
        await RutaConductorViewModel.mostrarNotificacion(
          'Cliente asignado',
          'Viaja a recogerlo.',
        );
      } else {
        await RutaConductorViewModel.mostrarNotificacion(
          'Solicitud activa',
          'Continúa el servicio.',
        );
      }
      await vm.guardarSolicitudActiva(widget.idSolicitud);
      await vm.cargarDatosCliente(widget.idSolicitud);
      await _cargarMarcadoresPersonalizados();
      vm.iniciarChat(widget.idSolicitud);
      vm.escucharEstadoSolicitud(widget.idSolicitud, context);
      await _obtenerUbicacionConductor();
      await vm.iniciarTrackingUbicacion(widget.idSolicitud);
    });
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final clienteIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_red.png',
      size: const Size(106, 106),
    );
    if (!mounted) return;
    setState(() {
      _clienteMarkerIcon = clienteIcon;
    });
  }

  // Inicia el tracking de ubicación en segundo plano
  Future<void> iniciarTrackingBackground() async {
    try {
      debugPrint('[LOG] Iniciando tracking background');
      await PermissionsHelper.requestLocationPermission();
      await initializeBackgroundService();
      await startBackgroundTrackingService();
    } catch (e) {
      debugPrint('Error iniciando tracking background: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint('[LOG] App en background, iniciando tracking segundo plano');
      iniciarTrackingBackground();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[LOG] App en foreground, deteniendo tracking segundo plano');
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_rutaConductorOverlayStyle);
      detenerTrackingBackground();
      _actualizarUbicacionConductorEnFirestoreConConexion();
    }
  }

  // Actualiza ubicación solo si hay conexión, reintenta si falla
  Future<void> _actualizarUbicacionConductorEnFirestoreConConexion() async {
    final tieneConexion = await _tieneConexionInternet();
    if (!tieneConexion) {
      debugPrint('[LOG] Sin conexión, reintentando en 5s...');
      Future.delayed(const Duration(seconds: 5), () {
        _actualizarUbicacionConductorEnFirestoreConConexion();
      });
      return;
    }
    await _actualizarUbicacionConductorEnFirestore();
  }

  Future<void> _actualizarUbicacionConductorEnFirestore() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final nuevaUbicacion = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _ubicacionConductor = nuevaUbicacion;
      });
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.idSolicitud)
          .update({
            'conductor.ubicacion': {
              'lat': nuevaUbicacion.latitude,
              'lng': nuevaUbicacion.longitude,
            },
          });
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('Error actualizando ubicación al reanudar: $e');
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _obtenerUbicacionConductor() async {
    if (!mounted) return;
    setState(() {
      _loadingUbicacion = true;
    });
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _ubicacionConductor = LatLng(position.latitude, position.longitude);
        _loadingUbicacion = false;
      });
      // Centrar ambos marcadores y ajustar zoom (no centrar solo el conductor)
      _fitMarkers();

      _escucharMovimientoConductor();

      // Obtener polyline de Google Directions API
      final vm = Provider.of<RutaConductorViewModel>(context, listen: false);
      if (_ubicacionConductor != null &&
          vm.latCliente != null &&
          vm.lngCliente != null) {
        if (!mounted) return;
        setState(() {
          _loadingPolyline = true;
        });
        try {
          final direcciones = Direcciones();
          String? polyline = await direcciones.getPolyline(
            _ubicacionConductor!.latitude,
            _ubicacionConductor!.longitude,
            vm.latCliente!,
            vm.lngCliente!,
          );
          if (polyline != null && polyline.isNotEmpty) {
            _polylinePoints = _decodePolyline(polyline);
          } else {
            _polylinePoints = [];
          }
        } catch (e) {
          _polylinePoints = [];
          debugPrint('Error obteniendo polyline: $e');
        }
        setState(() {
          _loadingPolyline = false;
        });
        if (!mounted) return;
        setState(() {
          _loadingPolyline = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUbicacion = false;
      });
      debugPrint('Error obteniendo ubicación: $e');
    }
  }

  void _escucharMovimientoConductor() {
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1, // Actualiza cada 15 metros de movimiento
          ),
        ).listen((Position position) async {
          final nuevaUbicacion = LatLng(position.latitude, position.longitude);

          if (!mounted) return;
          setState(() {
            _ubicacionConductor = nuevaUbicacion;
            _fechaUbicacionObtenida = DateTime.now();
          });

          // Guardar ubicación obtenida y fecha en Firestore
          try {
            final fechaEnvio =
                _fechaUbicacionObtenida?.toIso8601String() ??
                DateTime.now().toIso8601String();
            await FirebaseFirestore.instance
                .collection('solicitudes')
                .doc(widget.idSolicitud)
                .update({
                  'conductor.ubicacion': {
                    'lat': nuevaUbicacion.latitude,
                    'lng': nuevaUbicacion.longitude,
                    'fecha': fechaEnvio,
                  },
                });
            // Leer la ubicación enviada desde Firestore para mostrarla en la modal
            final doc = await FirebaseFirestore.instance
                .collection('solicitudes')
                .doc(widget.idSolicitud)
                .get();
            final ubicacionEnviada = doc.data()?['conductor']?['ubicacion'];
            if (ubicacionEnviada != null) {
              if (!mounted) return;
              setState(() {});
            }
          } catch (e) {
            debugPrint('Error guardando ubicación obtenida: $e');
          }

          if (_mapController != null && _polylinePoints.isNotEmpty) {
            LatLng siguientePunto = _polylinePoints[0];
            _bearing = Mapa.calcularBearing(
              _ubicacionConductor!.latitude,
              _ubicacionConductor!.longitude,
              siguientePunto.latitude,
              siguientePunto.longitude,
            );
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: nuevaUbicacion,
                  zoom: 17,
                  tilt: 0,
                  bearing: _bearing,
                ),
              ),
            );
          }

          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            setState(() {});
          });
        });
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _centerOnConductor() {
    if (_mapController != null && _ubicacionConductor != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_ubicacionConductor!, 16),
      );
    }
  }

  void _fitMarkers() {
    if (_mapController == null) return;

    final vm = Provider.of<RutaConductorViewModel>(context, listen: false);

    if (_ubicacionConductor == null ||
        vm.latCliente == null ||
        vm.lngCliente == null)
      return;

    final cliente = LatLng(vm.latCliente!, vm.lngCliente!);

    // Calcular bearing del conductor hacia el cliente
    final bearing = Mapa.calcularBearing(
      _ubicacionConductor!.latitude,
      _ubicacionConductor!.longitude,
      cliente.latitude,
      cliente.longitude,
    );

    // Centrar la cámara en el conductor, mirando hacia el cliente
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _ubicacionConductor!,
          zoom: 16,
          tilt: 0,
          bearing: bearing,
        ),
      ),
    );
  }

  // Calcula la distancia en kilómetros entre conductor y cliente
  String _distanciaKmConductorCliente() {
    final vm = Provider.of<RutaConductorViewModel>(context, listen: false);
    if (_ubicacionConductor == null ||
        vm.latCliente == null ||
        vm.lngCliente == null) {
      return "--";
    }
    final double distanciaMetros = Geolocator.distanceBetween(
      _ubicacionConductor!.latitude,
      _ubicacionConductor!.longitude,
      vm.latCliente!,
      vm.lngCliente!,
    );
    if (distanciaMetros < 1000) {
      return "${distanciaMetros.round()} m";
    } else {
      final double distanciaKm = distanciaMetros / 1000.0;
      return "${distanciaKm.toStringAsFixed(2)} km";
    }
  }

  // Calcula el tiempo estimado de llegada
  String _tiempoEstimadoLlegada() {
    final vm = Provider.of<RutaConductorViewModel>(context, listen: false);
    // Si no hay ubicaciones, muestra vacío
    if (_ubicacionConductor == null ||
        vm.latCliente == null ||
        vm.lngCliente == null) {
      return "Tiempo estimado: --";
    }
    // Calcula distancia en km
    final double distancia =
        Geolocator.distanceBetween(
          _ubicacionConductor!.latitude,
          _ubicacionConductor!.longitude,
          vm.latCliente!,
          vm.lngCliente!,
        ) /
        1000.0;
    // Supón velocidad promedio 40km/h
    final double velocidad = 40.0;
    final double tiempoHoras = distancia / velocidad;
    final int minutos = (tiempoHoras * 60).round();
    return "Tiempo estimado: ${minutos} min";
  }

  Future<void> _marcarMensajesComoLeidos(RutaConductorViewModel vm) async {
    final conductorId = vm.conductorId;
    if (conductorId == null || conductorId.isEmpty) return;

    final pendientes = vm.mensajes
        .where(
          (m) => m.senderId != conductorId && !(m.readBy[conductorId] ?? false),
        )
        .toList();

    if (pendientes.isEmpty) return;

    await Future.wait(
      pendientes.map(
        (m) => vm.chatService.markMessageRead(
          solicitudId: widget.idSolicitud,
          messageId: m.id,
          userId: conductorId,
        ),
      ),
    );
  }

  Widget _mapWidget(BuildContext context) {
    final vm = Provider.of<RutaConductorViewModel>(context);
    LatLng? clienteLatLng;
    if (vm.latCliente != null && vm.lngCliente != null) {
      clienteLatLng = LatLng(vm.latCliente!, vm.lngCliente!);
    }
    final target = clienteLatLng ?? _initialTarget;
    final markers = <Marker>{
      if (clienteLatLng != null)
        Marker(
          markerId: const MarkerId('cliente'),
          position: clienteLatLng,
          infoWindow: const InfoWindow(title: 'Cliente'),
          icon:
              _clienteMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      // if (_ubicacionConductor != null)
      //   Marker(
      //     markerId: const MarkerId('conductor'),
      //     position: _ubicacionConductor!,
      //     rotation: _bearing,
      //     anchor: const Offset(0.5, 0.5),
      //     flat: true,
      //     // infoWindow: const InfoWindow(title: 'Tú'),
      //     // icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      //   ),
    };
    final polylines = <Polyline>{
      if (_polylinePoints.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('google_route'),
          points: _polylinePoints,
          color: AppColores.primary,
          width: 5,
        )
      else if (_ubicacionConductor != null && clienteLatLng != null)
        Polyline(
          polylineId: const PolylineId('ruta_conductor_cliente'),
          points: [_ubicacionConductor!, clienteLatLng],
          color: AppColores.primary,
          width: 5,
        ),
    };
    if (_polylinePoints.isEmpty) {
      debugPrint('Polyline vacia, usando linea recta.');
    } else {
      debugPrint('Polyline de Google Directions cargada.');
    }
    debugPrint('Puntos polyline cargados: ${_polylinePoints.length}');
    return Stack(
      children: [
        Mapagoogle(
          initialTarget: target,
          initialZoom: _initialZoom,
          markers: markers,
          polylines: polylines,
          circles: _circles,
          myLocationEnabled: true,
          //myLocationButtonEnabled: true,
          onMapCreated: (controller) {
            _mapController = controller;
            // No llamar _fitMarkers aquí, se llama tras obtener ubicación
          },
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
                  colors: [Colors.black.withOpacity(0.28), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        if (_loadingUbicacion || _loadingPolyline)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.2),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _infoRow() {
    final vm = Provider.of<RutaConductorViewModel>(context);
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double avatarRadius = isTablet ? 60 : 40;
    final double padding = isTablet ? 28 : 10;
    final double spacing = isTablet ? 24 : 16;
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: avatarRadius,
            backgroundColor: AppColores.primary,
            backgroundImage: vm.fotoCliente.isNotEmpty
                ? CachedNetworkImageProvider(vm.fotoCliente)
                : null,
            child: vm.fotoCliente.isEmpty
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          SizedBox(width: spacing),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenW = constraints.maxWidth;
                    double nameFont = 25;
                    double addressFont = 18;
                    double spacing = 6;
                    if (screenW >= 1000) {
                      nameFont = 32;
                      addressFont = 22;
                      spacing = 12;
                    } else if (screenW < 350) {
                      nameFont = 18;
                      addressFont = 14;
                      spacing = 4;
                    } else if (screenW < 500) {
                      nameFont = 20;
                      addressFont = 15;
                      spacing = 5;
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vm.nombreCliente.isNotEmpty
                              ? vm.nombreCliente
                              : "Cliente",
                          style: TextStyle(
                            fontSize: nameFont,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: spacing),
                        Text(
                          vm.direccionCliente,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: addressFont,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: Image.asset(
                  'assets/img/icon_location.png',
                  width: avatarRadius * 0.8,
                  height: avatarRadius * 0.8,
                ),
                onPressed: () async {
                  await _marcarMensajesComoLeidos(vm);
                  if (_ubicacionConductor != null &&
                      vm.latCliente != null &&
                      vm.lngCliente != null) {
                    final origen =
                        '${_ubicacionConductor!.latitude},${_ubicacionConductor!.longitude}';
                    final destino = '${vm.latCliente},${vm.lngCliente}';
                    final url =
                        'https://www.google.com/maps/dir/?api=1&origin=$origen&destination=$destino&travelmode=driving';
                    try {
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (e) {
                      debugPrint('No se pudo abrir Google Maps: $e');
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ubicación no disponible')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomButtons() {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double buttonFontSize = isTablet ? 22 : 16;
    final double buttonPaddingV = isTablet ? 24 : 12;
    final double buttonIconSize = isTablet ? 32 : 22;
    final double buttonBorderRadius = isTablet ? 24 : 16;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: EdgeInsets.all(isTablet ? 20 : 8),
            child: Row(
              children: [
                Flexible(
                  flex: 1,
                  child: Consumer<RutaConductorViewModel>(
                    builder: (context, vm, _) {
                      final conductorId = vm.conductorId ?? '';
                      final mensajesPendientes = vm.mensajes
                          .where(
                            (m) =>
                                m.senderId != conductorId &&
                                (!(m.readBy[conductorId] ?? false)),
                          )
                          .length;
                      return Stack(
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppColores.primary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  buttonBorderRadius,
                                ),
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: buttonPaddingV,
                              ),
                              backgroundColor: Colors.white,
                            ),
                            onPressed: _chatModalAbierto
                                ? null
                                : () async {
                                    setState(() {
                                      _chatModalAbierto = true;
                                    });
                                    try {
                                      await _marcarMensajesComoLeidos(vm);
                                      if (!mounted) return;
                                      await showModalBottomSheet(
                                        context: this.context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.white,
                                        useSafeArea: true,
                                        builder: (_) => UniversalChatWidget(
                                          solicitudId: widget.idSolicitud,
                                          chatTitle: 'Chat con el cliente',
                                          backgroundColor:
                                              AppColores.background,
                                          myMessageColor: AppColores.primary,
                                          otherMessageColor: Colors.white,
                                          sendButtonColor: AppColores.primary,
                                          autoFocus: true,
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _chatModalAbierto = false;
                                        });
                                      }
                                    }
                                  },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat,
                                  color: AppColores.primary,
                                  size: buttonIconSize,
                                ),
                                SizedBox(width: isTablet ? 16 : 8),
                                Flexible(
                                  child: Text(
                                    "Chat",
                                    style: TextStyle(
                                      color: AppColores.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: buttonFontSize,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (mensajesPendientes > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: EdgeInsets.all(isTablet ? 6 : 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: BoxConstraints(
                                  minWidth: isTablet ? 28 : 20,
                                  minHeight: isTablet ? 28 : 20,
                                ),
                                child: Center(
                                  child: Text(
                                    mensajesPendientes.toString(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isTablet ? 16 : 12,
                                      fontWeight: FontWeight.bold,
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
                SizedBox(width: isTablet ? 24 : 12),
                Flexible(
                  flex: 1,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(buttonBorderRadius),
                      ),
                      padding: EdgeInsets.symmetric(vertical: buttonPaddingV),
                      elevation: 0,
                    ),
                    onPressed: _yaLleguePressed
                        ? null
                        : () async {
                            setState(() {
                              _yaLleguePressed = true;
                            });
                            try {
                              await FirebaseFirestore.instance
                                  .collection('solicitudes')
                                  .doc(widget.idSolicitud)
                                  .update({'estado': 'en camino'});
                            } catch (e) {
                              debugPrint('Error al cambiar estado: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('No se pudo cambiar el estado'),
                                ),
                              );
                              setState(() {
                                _yaLleguePressed = false;
                              });
                              return;
                            }
                            if (!mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => ChangeNotifierProvider(
                                  create: (_) => RutaDestinoViewModel(),
                                  child: RutaDestino(
                                    idSolicitud: widget.idSolicitud,
                                  ),
                                ),
                              ),
                            );
                          },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check,
                          color: Colors.white,
                          size: buttonIconSize,
                        ),
                        SizedBox(width: isTablet ? 16 : 8),
                        Flexible(
                          child: Text(
                            "Ya llegue",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: buttonFontSize,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _rutaConductorOverlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ...existing code...
            Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(flex: 2, child: _mapWidget(context)),
                Flexible(
                  flex: 1,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 18,
                          offset: Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.route,
                                  color: AppColores.buttonPrimary,
                                  size: 26,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Ruta al cliente",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 0,
                                    horizontal: 5,
                                  ),
                                  child: _infoRow(),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 0,
                                    horizontal: 4,
                                  ),
                                  child: _bottomButtons(),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // ...existing code...
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _tiempoEstimadoLlegada(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            // ...existing code...
            Positioned(
              left: 24,
              bottom: MediaQuery.of(context).size.height * 0.35,
              child: FloatingActionButton.extended(
                heroTag: "fab_distancia",
                backgroundColor: Colors.white,
                icon: const Icon(Icons.directions_car, color: Colors.black),
                label: Text(
                  _distanciaKmConductorCliente(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onPressed: () {}, // Solo informativo
                elevation: 2,
              ),
            ),
            // ...existing code...
            Positioned(
              right: 24,
              bottom: MediaQuery.of(context).size.height * 0.35, // Más alto
              child: FloatingActionButton(
                heroTag: "fab_centrar",
                backgroundColor: AppColores.buttonPrimary,
                child: Icon(
                  _centraSoloConductor ? Icons.person_pin_circle : Icons.group,
                ),
                onPressed: () {
                  setState(() {
                    if (_centraSoloConductor) {
                      _centerOnConductor();
                    } else {
                      _fitMarkers();
                    }
                    _centraSoloConductor = !_centraSoloConductor;
                  });
                },
              ),
            ),
            // ...existing code...
          ],
        ),
      ),
    );
  }
}
