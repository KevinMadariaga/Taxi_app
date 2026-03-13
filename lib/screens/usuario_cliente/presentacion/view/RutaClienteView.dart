

import 'dart:async';
import 'dart:math' as Math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/services/DireccionesServicio.dart';
import 'package:taxi_app/widgets/LoaderCancelado.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/universal_chat_widget.dart';
import 'package:taxi_app/core/app_colores.dart';


class RutaCliente extends StatefulWidget {
  final String idSolicitud;
  const RutaCliente({Key? key, required this.idSolicitud}) : super(key: key);

  @override
  State<RutaCliente> createState() => _RutaClienteState();
}

class _RutaClienteState extends State<RutaCliente> with WidgetsBindingObserver {

    String? _tiempoEstimadoTexto;
    Future<void> _actualizarTiempoEstimado() async {
      if (_conductorLatLng != null) {
        final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
        LatLng? clienteLatLng = (vm.latCliente != null && vm.lngCliente != null)
            ? LatLng(vm.latCliente!, vm.lngCliente!)
            : null;
        if (clienteLatLng != null) {
          final direcciones = Direcciones();
          int? segundos = await direcciones.getEstimatedDuration(
            _conductorLatLng!.latitude,
            _conductorLatLng!.longitude,
            clienteLatLng.latitude,
            clienteLatLng.longitude,
          );
          setState(() {
            if (segundos != null) {
              final minutos = (segundos / 60).ceil();
              _tiempoEstimadoTexto = minutos > 1 ? "$minutos min" : "1 min";
            } else {
              _tiempoEstimadoTexto = null;
            }
          });
        }
      }
    }

    LatLng? _conductorLatLng;
    StreamSubscription? _conductorLocationSub;
    Timer? _animacionMarcadorTimer;

  List<LatLng> _polylinePoints = [];


  Future<void> _obtenerPolyline(LatLng origen, LatLng destino) async {
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
      } else {
        _polylinePoints = [];
      }
    } catch (e) {
      _polylinePoints = [];
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
      vm.inicializarNotificaciones();
      await vm.mostrarNotificacion(
        'Conductor asignado',
        'Vendrá pronto a recogerte.',
      );
      vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
      vm.iniciarChat(widget.idSolicitud);
      vm.escucharEstadoSolicitud(widget.idSolicitud, context);
      LatLng? prevClienteLatLng;
      LatLng? prevConductorLatLng;
      vm.addListener(() {
        if (_mapController != null) {
          LatLng? clienteLatLng =
              (vm.latCliente != null && vm.lngCliente != null)
              ? LatLng(vm.latCliente!, vm.lngCliente!)
              : null;
          LatLng? conductorLatLng =
              (vm.latConductor != null && vm.lngConductor != null)
              ? LatLng(vm.latConductor!, vm.lngConductor!)
              : null;
          // Solo actualizar polyline si ambos existen
          if (clienteLatLng != null && conductorLatLng != null) {
            _obtenerPolyline(conductorLatLng, clienteLatLng);
          }
        }
      });
    });

    // Escuchar ubicación del conductor en tiempo real desde Firestore
    _conductorLocationSub = FirebaseFirestore.instance
      .collection('solicitudes')
      .doc(widget.idSolicitud)
      .snapshots()
      .listen((doc) {
        final ubicacion = doc.data()?['conductor']?['ubicacion'];
        if (ubicacion != null) {
          final lat = ubicacion['lat'] ?? 0.0;
          final lng = ubicacion['lng'] ?? 0.0;
          final fecha = ubicacion['fecha'] ?? '';
          setState(() {
            _conductorLatLng = LatLng(lat, lng);
          });
          // Animar marcador y cámara
          _animarMarcadorConductorSuave(_conductorLatLng!);
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(_conductorLatLng!),
            );
          }
        }
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animacionMarcadorTimer?.cancel();
    _conductorLocationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Al volver a la app, solo actualizar la posición del marcador del conductor
      final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
      vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
      // Si hay nueva ubicación, solo mover el marcador
      LatLng? nuevaLatLng = (vm.latConductor != null && vm.lngConductor != null)
          ? LatLng(vm.latConductor!, vm.lngConductor!)
          : null;
      if (nuevaLatLng != null) {
        setState(() {
          _conductorLatLng = nuevaLatLng;
        });
      }
    }
    // Puedes agregar lógica en onPause si lo necesitas
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
        return;
      }
      double lat = inicio.latitude + (destino.latitude - inicio.latitude) * pasoActual / pasos;
      double lng = inicio.longitude + (destino.longitude - inicio.longitude) * pasoActual / pasos;
      LatLng nuevaPos = LatLng(lat, lng);
      _conductorLatLng = nuevaPos;
      _centrarAmbosMarcadores();
      _actualizarTiempoEstimado();
      setState(() {});
      pasoActual++;
    });

  }

  // Centra ambos marcadores (cliente y conductor) en pantalla
  void _centrarAmbosMarcadores() {
    final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
    LatLng? clienteLatLng = (vm.latCliente != null && vm.lngCliente != null)
        ? LatLng(vm.latCliente!, vm.lngCliente!)
        : null;
    LatLng? conductorLatLng = _conductorLatLng;
    if (_mapController != null && clienteLatLng != null && conductorLatLng != null) {
      // Calcular bounds para ambos marcadores
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          clienteLatLng.latitude < conductorLatLng.latitude ? clienteLatLng.latitude : conductorLatLng.latitude,
          clienteLatLng.longitude < conductorLatLng.longitude ? clienteLatLng.longitude : conductorLatLng.longitude,
        ),
        northeast: LatLng(
          clienteLatLng.latitude > conductorLatLng.latitude ? clienteLatLng.latitude : conductorLatLng.latitude,
          clienteLatLng.longitude > conductorLatLng.longitude ? clienteLatLng.longitude : conductorLatLng.longitude,
        ),
      );
      // Mostrar polyline
      if (_polylinePoints.isEmpty) {
        _obtenerPolyline(conductorLatLng, clienteLatLng);
      }
      // Calcular bearing del cliente hacia el conductor
      double bearing = _calcularBearing(
        clienteLatLng.latitude,
        clienteLatLng.longitude,
        conductorLatLng.latitude,
        conductorLatLng.longitude,
      );
      // Centrar la cámara para que ambos marcadores sean visibles, con bearing
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 120),
      );
      // Opcional: animar luego la perspectiva del cliente
      Future.delayed(const Duration(milliseconds: 400), () {
        double distancia = _calcularDistancia(clienteLatLng, conductorLatLng);
        double zoom = _zoomPorDistancia(distancia);
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: clienteLatLng,
              zoom: zoom,
              bearing: bearing,
              tilt: 0,
            ),
          ),
        );
      });
      _actualizarTiempoEstimado();
    }
  }

//animacion de camara desde la perspectiva del cliente mirando al conductor
  void _animarCamaraPerspectiva(LatLng conductorLatLng) {
    if (_mapController == null) return;
    final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
    LatLng? clienteLatLng = (vm.latCliente != null && vm.lngCliente != null)
        ? LatLng(vm.latCliente!, vm.lngCliente!)
        : null;
    if (clienteLatLng == null) return;

    // Calcular bearing desde el cliente hacia el conductor
    double bearing = _calcularBearing(
      clienteLatLng.latitude,
      clienteLatLng.longitude,
      conductorLatLng.latitude,
      conductorLatLng.longitude,
    );

    // Calcular zoom dinámico según distancia
    double distancia = _calcularDistancia(clienteLatLng, conductorLatLng);
    double zoom = _zoomPorDistancia(distancia);

    // Animar la cámara desde la perspectiva del cliente mirando al conductor
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: clienteLatLng,
          zoom: zoom,
          bearing: bearing,
          tilt: 45,
        ),
      ),
    );
  }

  double _calcularBearing(double lat1, double lng1, double lat2, double lng2) {
    double dLon = (lng2 - lng1) * (3.141592653589793 / 180.0);
    double y = Math.sin(dLon) * Math.cos(lat2 * (3.141592653589793 / 180.0));
    double x = Math.cos(lat1 * (3.141592653589793 / 180.0)) * Math.sin(lat2 * (3.141592653589793 / 180.0)) -
        Math.sin(lat1 * (3.141592653589793 / 180.0)) * Math.cos(lat2 * (3.141592653589793 / 180.0)) * Math.cos(dLon);
    double bearing = Math.atan2(y, x);
    bearing = bearing * (180.0 / 3.141592653589793);
    return (bearing + 360.0) % 360.0;
  }

  double _calcularDistancia(LatLng a, LatLng b) {
    const R = 6371.0; // Radio de la Tierra en km
    double dLat = (b.latitude - a.latitude) * (3.141592653589793 / 180.0);
    double dLon = (b.longitude - a.longitude) * (3.141592653589793 / 180.0);
    double lat1 = a.latitude * (3.141592653589793 / 180.0);
    double lat2 = b.latitude * (3.141592653589793 / 180.0);
    double aVal = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.sin(dLon / 2) * Math.sin(dLon / 2) * Math.cos(lat1) * Math.cos(lat2);
    double c = 2 * Math.atan2(Math.sqrt(aVal), Math.sqrt(1 - aVal));
    return R * c * 1000; // metros
  }

  double _zoomPorDistancia(double distancia) {
    // Zoom adaptativo: más cerca, más zoom (valores aumentados)
    if (distancia < 100) return 20.0;
    if (distancia < 300) return 19.0;
    if (distancia < 800) return 18.0;
    if (distancia < 2000) return 17.0;
    if (distancia < 5000) return 16.0;
    return 15.0;
  }


  @override
  Widget build(BuildContext context) {
    // Cambiar a variable de estado para alternar entre vistas
    bool mostrarSoloCliente = false;
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
          body: Consumer<Rutaclienteviewmodel>(
            builder: (context, vm, _) {
              final size = MediaQuery.of(context).size;
              final double screenW = size.width;
              final bool isTablet = screenW >= 1000;
              LatLng? clienteLatLng =
                  (vm.latCliente != null && vm.lngCliente != null)
                  ? LatLng(vm.latCliente!, vm.lngCliente!)
                  : null;
              LatLng? conductorLatLng = _conductorLatLng ?? ((vm.latConductor != null && vm.lngConductor != null)
                  ? LatLng(vm.latConductor!, vm.lngConductor!)
                  : null);
              final markers = <Marker>{
                if (mostrarSoloCliente && clienteLatLng != null)
                  // ignore: dead_code
                  Marker(
                    markerId: const MarkerId('cliente'),
                    position: clienteLatLng,
                    infoWindow: const InfoWindow(title: 'Cliente'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
                if (!mostrarSoloCliente && conductorLatLng != null)
                  Marker(
                    markerId: const MarkerId('conductor'),
                    position: conductorLatLng,
                    infoWindow: const InfoWindow(title: 'Conductor'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                  ),
                if (!mostrarSoloCliente && clienteLatLng != null)
                  Marker(
                    markerId: const MarkerId('cliente'),
                    position: clienteLatLng,
                    infoWindow: const InfoWindow(title: 'Cliente'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
              };
              return Column(
                children: [
                  // Mapa ocupa la parte superior
                  Expanded(
                    flex: 2,
                    child: Stack(
                      children: [
                        _MapWidget(
                          markers: markers,
                          conductorLatLng: conductorLatLng,
                          clienteLatLng: clienteLatLng,
                          mapControllerSetter: (controller) =>
                              _mapController = controller,
                        ),
                        if (_tiempoEstimadoTexto != null)
                          Positioned(
                            top: 55,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.timer, color: AppColores.primary),
                                    SizedBox(width: 8),
                                    Text(
                                      'Tiempo estimado: $_tiempoEstimadoTexto',
                                      style: TextStyle(
                                        color: AppColores.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
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
                  // Card ocupa la parte inferior
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: EdgeInsets.only(top: isTablet ? 16 : 8),
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
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 12, vertical: isTablet ? 24 : 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _infoRow(),
                            SizedBox(height: isTablet ? 12 : 8),
                            _bottomButtons(),
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
  }
  // Mosstrar información del conductor y vehículo en un card debajo del mapa
  Widget _infoRow() {
    final vm = Provider.of<Rutaclienteviewmodel>(context);
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 12;
    final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
    final double avatarRadius = isTablet ? 60 : screenW < 350 ? 22 : 40;
    final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 12;
    final double nameFontSize = isTablet ? 32 : screenW < 350 ? 12 : 18;
    final double placaFontSize = isTablet ? 22 : screenW < 350 ? 10 : 15;
    final double imageW = isTablet ? 160 : screenW < 350 ? 60 : 100;
    final double imageH = isTablet ? 120 : screenW < 350 ? 40 : 70;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(isTablet ? 24 : screenW < 350 ? 8 : 12),
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
                      padding: EdgeInsets.all(isTablet ? 12 : screenW < 350 ? 2 : 6),
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
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 8, vertical: isTablet ? 6 : 2),
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
                  width: isTablet ? 48 : screenW < 350 ? 8 : size.width * 0.12,
                ),
                if (vm.fotoVehiculo.isNotEmpty)
                  Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(isTablet ? 10 : screenW < 350 ? 2 : 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(isTablet ? 18 : screenW < 350 ? 6 : 12),
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
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 8, vertical: isTablet ? 6 : 2),
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
      final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
      final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
      final double buttonFontSize = isTablet ? 22 : screenW < 350 ? 13 : 18;
      final double buttonIconSize = isTablet ? 32 : screenW < 350 ? 18 : 24;
      final double buttonBorderRadius = isTablet ? 24 : screenW < 350 ? 8 : 12;
      final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 16;
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

    void limpiarMensajesPendientes(BuildContext context) async {
      final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
      final usuarioId = vm.usuarioId;
      for (final m in vm.mensajes) {
        if (usuarioId != null &&
            m.senderId != usuarioId &&
            !(m.readBy[usuarioId] ?? false)) {
          await vm.chatService.markMessageRead(
            solicitudId: widget.solicitudId,
            messageId: m.id,
            userId: usuarioId,
          );
        }
      }
    }

    @override
    Widget build(BuildContext context) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: widget.isTablet ? 70 : widget.spacing < 8 ? 40 : 56,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppColores.primary,
                  width: 2.5,
                ),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
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
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) {
                    return Dialog(
                      insetPadding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      child: SafeArea(
                        child: Container(
                          width: double.infinity,
                          height: MediaQuery.of(context).size.height,
                          color: Colors.white,
                          child: UniversalChatWidget(
                            solicitudId: widget.solicitudId,
                            chatTitle: 'Chat con el conductor',
                            backgroundColor: Colors.white,
                            myMessageColor: AppColores.primary,
                            otherMessageColor: Colors.grey.shade200,
                            sendButtonColor: AppColores.primary,
                            autoFocus: true,
                          ),
                        ),
                      ),
                    );
                  },
                ).then((_) {
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
              top: widget.isTablet ? -12 : widget.spacing < 8 ? -4 : -8,
              child: Container(
                padding: EdgeInsets.all(widget.isTablet ? 10 : widget.spacing < 8 ? 3 : 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: widget.isTablet ? 3 : 2),
                ),
                constraints: BoxConstraints(
                  minWidth: widget.isTablet ? 36 : widget.spacing < 8 ? 14 : 24,
                  minHeight: widget.isTablet ? 36 : widget.spacing < 8 ? 14 : 24,
                ),
                child: Center(
                  child: Text(
                    widget.mensajesPendientes.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: widget.isTablet ? 22 : widget.spacing < 8 ? 8 : 14,
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

class _MapWidget extends StatelessWidget {
  final Set<Marker> markers;
  final LatLng? conductorLatLng;
  final LatLng? clienteLatLng;
  final Function(GoogleMapController) mapControllerSetter;
  const _MapWidget({
    required this.markers,
    required this.conductorLatLng,
    required this.clienteLatLng,
    required this.mapControllerSetter,
  });

  @override
  Widget build(BuildContext context) {
    final LatLng initialTarget = _getInitialTarget();
    final Set<Polyline> polylines = _getPolylines(context);
    return Stack(
      children: [
        Mapagoogle(
          initialTarget: initialTarget,
          initialZoom: 15.0,
          markers: markers,
          polylines: polylines,
          circles: {},
          //myLocationEnabled: true,
          onMapCreated: (controller) {
            mapControllerSetter(controller);
            _animateCameraToBounds(controller);
          },
        ),
        _CenterConductorButton(
          conductorLatLng: conductorLatLng,
          clienteLatLng: clienteLatLng,
        ),
      ],
    );
  }

  LatLng _getInitialTarget() {
    if (conductorLatLng != null && clienteLatLng != null) {
      return LatLng(
        (conductorLatLng!.latitude + clienteLatLng!.latitude) / 2,
        (conductorLatLng!.longitude + clienteLatLng!.longitude) / 2,
      );
    }
    return conductorLatLng ?? clienteLatLng ?? const LatLng(8.2595534, -73.353469);
  }

  Set<Polyline> _getPolylines(BuildContext context) {
    final state = context.findAncestorStateOfType<_RutaClienteState>();
    if (state != null && state._polylinePoints.isNotEmpty) {
      return {
        Polyline(
          polylineId: const PolylineId('google_route'),
          points: state._polylinePoints,
          color: AppColores.primary,
          width: 5,
        )
      };
    } else if (conductorLatLng != null && clienteLatLng != null) {
      return {
        Polyline(
          polylineId: const PolylineId('ruta_conductor_cliente'),
          points: [conductorLatLng!, clienteLatLng!],
          color: AppColores.primary,
          width: 5,
        )
      };
    }
    return {};
  }

  void _animateCameraToBounds(GoogleMapController controller) {
    if (conductorLatLng != null && clienteLatLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          conductorLatLng!.latitude < clienteLatLng!.latitude
              ? conductorLatLng!.latitude
              : clienteLatLng!.latitude,
          conductorLatLng!.longitude < clienteLatLng!.longitude
              ? conductorLatLng!.longitude
              : clienteLatLng!.longitude,
        ),
        northeast: LatLng(
          conductorLatLng!.latitude > clienteLatLng!.latitude
              ? conductorLatLng!.latitude
              : clienteLatLng!.latitude,
          conductorLatLng!.longitude > clienteLatLng!.longitude
              ? conductorLatLng!.longitude
              : clienteLatLng!.longitude,
        ),
      );
      Future.delayed(const Duration(milliseconds: 300), () {
        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      });
    }
  }
}

class _CenterConductorButton extends StatelessWidget {
  final LatLng? conductorLatLng;
  final LatLng? clienteLatLng;
  const _CenterConductorButton({
    required this.conductorLatLng,
    required this.clienteLatLng,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      right: 16,
      child: FloatingActionButton(
        heroTag: 'fab_centrar_conductor',
        backgroundColor: AppColores.primary,
        child: const Icon(Icons.person_pin_circle, color: Colors.white),
        onPressed: () {
          final mapState = context.findAncestorStateOfType<_RutaClienteState>();
          if (mapState?._mapController != null && conductorLatLng != null && clienteLatLng != null) {
            LatLngBounds bounds = LatLngBounds(
              southwest: LatLng(
                clienteLatLng!.latitude < conductorLatLng!.latitude ? clienteLatLng!.latitude : conductorLatLng!.latitude,
                clienteLatLng!.longitude < conductorLatLng!.longitude ? clienteLatLng!.longitude : conductorLatLng!.longitude,
              ),
              northeast: LatLng(
                clienteLatLng!.latitude > conductorLatLng!.latitude ? clienteLatLng!.latitude : conductorLatLng!.latitude,
                clienteLatLng!.longitude > conductorLatLng!.longitude ? clienteLatLng!.longitude : conductorLatLng!.longitude,
              ),
            );
            double bearing = mapState!._calcularBearing(
              clienteLatLng!.latitude,
              clienteLatLng!.longitude,
              conductorLatLng!.latitude,
              conductorLatLng!.longitude,
            );
            mapState._mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(
                    (clienteLatLng!.latitude + conductorLatLng!.latitude) / 2,
                    (clienteLatLng!.longitude + conductorLatLng!.longitude) / 2,
                  ),
                  zoom: 16,
                  bearing: bearing,
                  tilt: 0,
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
// ignore: unused_element
class _ActionButtonsWidget extends StatelessWidget {
  final Rutaclienteviewmodel vm;
  final String solicitudId;
  final GoogleMapController? mapController;
  final LatLng? clienteLatLng;
  final LatLng? conductorLatLng;
  const _ActionButtonsWidget({
    required this.vm,
    required this.solicitudId,
    required this.mapController,
    required this.clienteLatLng,
    required this.conductorLatLng,
  });

  @override
  Widget build(BuildContext context) {
    final double screenW = MediaQuery.of(context).size.width;
    final bool isTablet = screenW >= 1000;
    final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
    final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
    final double buttonFontSize = isTablet ? 22 : screenW < 350 ? 13 : 18;
    final double buttonIconSize = isTablet ? 32 : screenW < 350 ? 18 : 24;
    final double buttonBorderRadius = isTablet ? 24 : screenW < 350 ? 8 : 12;
    final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 16;
    int mensajesPendientes = vm.mensajesPendientes;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
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
              solicitudId: solicitudId,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            child: CancelButton(
              buttonIconSize: buttonIconSize,
              buttonFontSize: buttonFontSize,
              buttonBorderRadius: buttonBorderRadius,
              paddingV: paddingV,
              solicitudId: solicitudId,
            ),
          ),
        ],
      ),
    );
  }
}
