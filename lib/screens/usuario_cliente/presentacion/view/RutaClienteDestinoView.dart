import 'dart:async';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/services/DireccionesServicio.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:url_launcher/url_launcher.dart';

class RutaClienteDestino extends StatefulWidget {
  final String idSolicitud;
  const RutaClienteDestino({Key? key, required this.idSolicitud})
    : super(key: key);

  @override
  State<RutaClienteDestino> createState() => _RutaClienteDestinoState();
}

class _RutaClienteDestinoState extends State<RutaClienteDestino> with WidgetsBindingObserver {
    
  LatLng? _conductorLatLng;
    StreamSubscription<LatLng?>? _conductorLocationSub;
    StreamSubscription? _conductorLocationFirestoreSub;
  Timer? _animacionMarcadorTimer;

  List<LatLng> _polylinePoints = [];
  bool _loadingPolyline = false;

  Future<void> _obtenerPolyline(LatLng origen, LatLng destino) async {
    setState(() {
      _loadingPolyline = true;
    });
    try {
      final direcciones = Direcciones();
      String? polyline = await direcciones.getPolyline(
        origen.latitude,
        origen.longitude,
        destino.latitude,
        destino.longitude,
      );
      if (polyline != null && polyline.isNotEmpty) {
        _polylinePoints = _decodePolyline(polyline);
        // Ajustar cámara para mostrar toda la polyline
        if (_polylinePoints.length > 1 && _mapController != null) {
          LatLngBounds bounds = _calcularBoundsPolyline(_polylinePoints);
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 80),
          );
        }
      } else {
        _polylinePoints = [];
      }
    } catch (e) {
      _polylinePoints = [];
    }
    setState(() {
      _loadingPolyline = false;
    });
  }

  // ---
      // Función para calcular el bearing entre dos puntos

  LatLngBounds _calcularBoundsPolyline(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

// Animación suave para mover el marcador del conductor
                    void _animarMarcadorConductorSuave(LatLng nuevaLatLng) {
                      _animacionMarcadorTimer?.cancel();
                      final inicio = _conductorLatLng ?? nuevaLatLng;
                      final destino = nuevaLatLng;
                      const pasos = 30;
                      const duracion = Duration(milliseconds: 20);
                      int pasoActual = 0;
                      _animacionMarcadorTimer = Timer.periodic(duracion, (timer) {
                        if (pasoActual >= pasos) {
                          timer.cancel();
                          _conductorLatLng = destino;
                          setState(() {});
                          // Centrar el mapa en la posición final
                          if (_mapController != null) {
                            _mapController!.animateCamera(
                              CameraUpdate.newLatLng(destino),
                            );
                          }
                          return;
                        }
                        double lat = inicio.latitude + (destino.latitude - inicio.latitude) * pasoActual / pasos;
                        double lng = inicio.longitude + (destino.longitude - inicio.longitude) * pasoActual / pasos;
                        LatLng nuevaPos = LatLng(lat, lng);
                        _conductorLatLng = nuevaPos;
                        setState(() {});
                        // Centrar el mapa en cada paso
                        if (_mapController != null) {
                          _mapController!.animateCamera(
                            CameraUpdate.newLatLng(nuevaPos),
                          );
                        }
                        pasoActual++;
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

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Escuchar ubicación del conductor directamente en la colección 'solicitudes', campo 'conductor.ubicacion'
    final vm = Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
    _conductorLocationFirestoreSub = FirebaseService()
        .escucharUbicacionConductorEnSolicitud(widget.idSolicitud)
        .listen((ubicacion) {
          if (ubicacion != null) {
            debugPrint('[LOG] Ubicación del conductor traída de solicitudes/conductor.ubicacion: lat=${ubicacion.latitude}, lng=${ubicacion.longitude}');
            setState(() {
              _conductorLatLng = ubicacion;
            });
            _animarMarcadorConductorSuave(ubicacion);
          }
        });
    _conductorLocationSub?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Guardar el id de la solicitud activa
      await SessionHelper.setActiveSolicitud(widget.idSolicitud);
      final vm = Provider.of<Rutaclientedestinoviewmodel>(
        context,
        listen: false,
      );
      vm.inicializarNotificaciones();
      await vm.mostrarNotificacion(
        'Conductor en marcha',
        'Conductor está en camino al destino. ¡Prepárate para tu viaje!',
      );
      vm.cargarDatosConductorYUbicacionDestino(widget.idSolicitud);
      vm.escucharEstadoSolicitud(widget.idSolicitud, context);
      vm.addListener(() {
        // Detectar navegación automática a RutaClienteDestino
        if (vm.estado.toLowerCase() == 'en camino') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ChangeNotifierProvider(
                  create: (_) => Rutaclientedestinoviewmodel(),
                    
                  builder: (context, child) {
                    // Usar el contexto correcto para el Provider
                    return RutaClienteDestino(idSolicitud: widget.idSolicitud);
                  },
                ),
              ),
            );
        }
        if (_mapController != null) {
          LatLng? destinoLatLng =
              (vm.latDestino != null && vm.lngDestino != null)
              ? LatLng(vm.latDestino!, vm.lngDestino!)
              : null;
          LatLng? conductorLatLng =
              (vm.latConductor != null && vm.lngConductor != null)
              ? LatLng(vm.latConductor!, vm.lngConductor!)
              : null;
          if (conductorLatLng != null && destinoLatLng != null) {
            final bounds = LatLngBounds(
              southwest: LatLng(
                conductorLatLng.latitude < destinoLatLng.latitude
                    ? conductorLatLng.latitude
                    : destinoLatLng.latitude,
                conductorLatLng.longitude < destinoLatLng.longitude
                    ? conductorLatLng.longitude
                    : destinoLatLng.longitude,
              ),
              northeast: LatLng(
                conductorLatLng.latitude > destinoLatLng.latitude
                    ? conductorLatLng.latitude
                    : destinoLatLng.latitude,
                conductorLatLng.longitude > destinoLatLng.longitude
                    ? conductorLatLng.longitude
                    : destinoLatLng.longitude,
              ),
            );
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 80),
            );
          } else if (conductorLatLng != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(conductorLatLng, 16),
            );
          } else if (destinoLatLng != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(destinoLatLng, 16),
            );
          }
          if (destinoLatLng != null && conductorLatLng != null) {
            _obtenerPolyline(conductorLatLng, destinoLatLng);
          }
        }
      });
    });
  }

  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animacionMarcadorTimer?.cancel();
    _conductorLocationSub?.cancel();
      _conductorLocationFirestoreSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Al volver a la app, actualizar datos de la solicitud (ubicación del conductor, estado, etc.)
      final vm = Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
      vm.cargarDatosConductorYUbicacionDestino(widget.idSolicitud);
    }
    // Puedes agregar lógica en onPause si lo necesitas
  }

  @override
  Widget build(BuildContext context) {
    bool mostrarSoloDestino = false;
    return WillPopScope(
      onWillPop: () async => false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: false,
          body: Consumer<Rutaclientedestinoviewmodel>(
            builder: (context, vm, _) {
              final size = MediaQuery.of(context).size;
              final double screenW = size.width;
              final bool isTablet = screenW >= 1000;
              final double paddingH = isTablet ? 32 : 12;
              final double paddingV = isTablet ? 24 : 10;
              final double spacing = isTablet ? 24 : 12;
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
                if (mostrarSoloDestino && destinoLatLng != null)
                  Marker(
                    markerId: const MarkerId('destino'),
                    position: destinoLatLng,
                    infoWindow: const InfoWindow(title: 'Destino'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
                if (!mostrarSoloDestino && conductorLatLng != null)
                  Marker(
                    markerId: const MarkerId('conductor'),
                    position: conductorLatLng,
                    infoWindow: const InfoWindow(title: 'Conductor'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                  ),
                if (!mostrarSoloDestino && destinoLatLng != null)
                  Marker(
                    markerId: const MarkerId('destino'),
                    position: destinoLatLng,
                    infoWindow: const InfoWindow(title: 'Destino'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
              };
              final polylines = <Polyline>{
                if (_polylinePoints.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('google_route'),
                    points: _polylinePoints,
                    color: AppColores.primary,
                    width: 5,
                  )
                else if (conductorLatLng != null && destinoLatLng != null)
                  Polyline(
                    polylineId: const PolylineId('ruta_conductor_destino'),
                    points: [conductorLatLng, destinoLatLng],
                    color: AppColores.primary,
                    width: 5,
                  ),
              };
              return Stack(
                children: [
                  SafeArea(
                    child: Column(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.63,
                          child: Stack(
                            children: [
                              _MapWidget(
                                markers: markers,
                                conductorLatLng: conductorLatLng,
                                destinoLatLng: destinoLatLng,
                                mapControllerSetter: (controller) =>
                                    _mapController = controller,
                              ),
                              Positioned(
                                top: 16,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(16),
                                    color: Colors.white,
                                    child: Container(
                                      width: 260,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.directions, color: AppColores.primary, size: 28),
                                              SizedBox(width: 10),
                                              Text(
                                                'Ruta hacia el destino',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 17,
                                                  color: AppColores.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.access_time, color: AppColores.primary, size: 22),
                                              SizedBox(width: 8),
                                              Text(
                                                vm.tiempoEstimado,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: AppColores.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 0,
                              right: 0,
                              top: isTablet ? 2 : 0,
                              bottom: 0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  margin: EdgeInsets.symmetric(horizontal: 0),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isTablet ? 8 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(0),
                                      bottomRight: Radius.circular(0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _infoRow(),
                                      SizedBox(height: isTablet ? 2 : 0),
                                      _bottomButtons(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  //posicionar el boton de mostrar solo destino/conductor
                  Positioned(
                    bottom: 330,
                    right: 20,
                    child: FloatingActionButton(
                      backgroundColor: AppColores.primary,
                      child: Icon(
                        mostrarSoloDestino
                            ? Icons.flag
                            : Icons.person_pin_circle,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          mostrarSoloDestino = !mostrarSoloDestino;
                          if (_mapController != null) {
                            if (mostrarSoloDestino && destinoLatLng != null) {
                              _mapController!.animateCamera(
                                CameraUpdate.newCameraPosition(
                                  CameraPosition(
                                    target: destinoLatLng,
                                    zoom: 16,
                                    tilt: 0,
                                  ),
                                ),
                              );
                            } else if (!mostrarSoloDestino && destinoLatLng != null && conductorLatLng != null) {
                              // Centrar ambos marcadores usando bounds
                              LatLngBounds bounds = LatLngBounds(
                                southwest: LatLng(
                                  destinoLatLng.latitude < conductorLatLng.latitude
                                      ? destinoLatLng.latitude
                                      : conductorLatLng.latitude,
                                  destinoLatLng.longitude < conductorLatLng.longitude
                                      ? destinoLatLng.longitude
                                      : conductorLatLng.longitude,
                                ),
                                northeast: LatLng(
                                  destinoLatLng.latitude > conductorLatLng.latitude
                                      ? destinoLatLng.latitude
                                      : conductorLatLng.latitude,
                                  destinoLatLng.longitude > conductorLatLng.longitude
                                      ? destinoLatLng.longitude
                                      : conductorLatLng.longitude,
                                ),
                              );
                              _mapController!.animateCamera(
                                CameraUpdate.newLatLngBounds(bounds, 80),
                              );
                            }
                          }
                        });
                      },
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
     final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
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
                final conductorLatLng = _conductorLatLng ??
                    ((vm.latConductor != null && vm.lngConductor != null)
                        ? LatLng(vm.latConductor!, vm.lngConductor!)
                        : null);
                if (conductorLatLng != null) {
                  final url = 'https://www.google.com/maps/search/?api=1&query=${conductorLatLng.latitude},${conductorLatLng.longitude}';
                  await Clipboard.setData(ClipboardData(text: url));
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (context) {
                      return Container(
                        height: MediaQuery.of(context).size.height * 0.5,
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Compartir ubicación',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                                final whatsappUrl = 'https://wa.me/?text=Ubicación%20del%20conductor:%20$url';
                                if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                                  await launchUrl(Uri.parse(whatsappUrl));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('No se pudo abrir WhatsApp'),
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
  const _MapWidget({
    required this.markers,
    required this.conductorLatLng,
    required this.destinoLatLng,
    required this.mapControllerSetter,
  });

  @override
  Widget build(BuildContext context) {
    // Obtener polylines desde el padre
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
          polylines:
              (context
                      .findAncestorStateOfType<_RutaClienteDestinoState>()
                      ?._polylinePoints
                      .isNotEmpty ==
                  true)
              ? {
                  Polyline(
                    polylineId: const PolylineId('google_route'),
                    points: context
                        .findAncestorStateOfType<_RutaClienteDestinoState>()!
                        ._polylinePoints,
                    color: AppColores.primary,
                    width: 5,
                  ),
                }
              : (conductorLatLng != null && destinoLatLng != null)
              ? {
                  Polyline(
                    polylineId: const PolylineId('ruta_conductor_destino'),
                    points: [conductorLatLng!, destinoLatLng!],
                    color: AppColores.primary,
                    width: 5,
                  ),
                }
              : {},
          circles: {},
          //myLocationEnabled: true,
          onMapCreated: (controller) {
            mapControllerSetter(controller);
            if (conductorLatLng != null && destinoLatLng != null) {
              final bounds = LatLngBounds(
                southwest: LatLng(
                  conductorLatLng!.latitude < destinoLatLng!.latitude
                      ? conductorLatLng!.latitude
                      : destinoLatLng!.latitude,
                  conductorLatLng!.longitude < destinoLatLng!.longitude
                      ? conductorLatLng!.longitude
                      : destinoLatLng!.longitude,
                ),
                northeast: LatLng(
                  conductorLatLng!.latitude > destinoLatLng!.latitude
                      ? conductorLatLng!.latitude
                      : destinoLatLng!.latitude,
                  conductorLatLng!.longitude > destinoLatLng!.longitude
                      ? conductorLatLng!.longitude
                      : destinoLatLng!.longitude,
                ),
              );
              Future.delayed(const Duration(milliseconds: 300), () {
                controller.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, 80),
                );
              });
            }
          },
        ),
      ],
    );
  }
}

