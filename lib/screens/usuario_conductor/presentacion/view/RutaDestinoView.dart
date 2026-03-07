
import 'dart:async';
import 'dart:math' as Math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaDestinoViewModel.dart';
import 'package:taxi_app/services/DireccionesServicio.dart';
import 'package:taxi_app/utils/Mapa.dart';
import 'package:taxi_app/widgets/LoaderCompletado.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaConductorViewModel.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as _logger;
import 'package:url_launcher/url_launcher.dart';

class RutaDestino extends StatefulWidget {

  final String idSolicitud;

  const RutaDestino({
    super.key,
    required this.idSolicitud,
  });

  @override
  State<RutaDestino> createState() => _RutaDestinoState();
}

class _RutaDestinoState extends State<RutaDestino> {

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

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

  @override
  void initState() {
    super.initState();

    // Inicializa notificaciones locales
    RutaConductorViewModel.inicializarNotificaciones();

    // Mostrar notificación local al iniciar la clase
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RutaDestinoViewModel.mostrarNotificacion(
        'Continúa el servicio',
        'Lleva el cliente a su destino.'
      );
      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      // Guardar el idSolicitud en cache al ingresar a la clase
      await vm.guardarSolicitudActiva(widget.idSolicitud);
      await vm.cargarDatosCliente(widget.idSolicitud);
      vm.iniciarChat(widget.idSolicitud);
      vm.escucharEstadoSolicitud(widget.idSolicitud, context);
      await _obtenerUbicacionConductor();
      // Inicia tracking de ubicación en background
      await vm.iniciarTrackingUbicacion(widget.idSolicitud);
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _obtenerUbicacionConductor() async {
    setState(() { _loadingUbicacion = true; });
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _ubicacionConductor = LatLng(position.latitude, position.longitude);
        _loadingUbicacion = false;
      });
      // Centrar ambos marcadores y ajustar zoom
      _fitMarkers();

      _escucharMovimientoConductor();

      // Obtener polyline de Google Directions API
      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      if (_ubicacionConductor != null && vm.latDestino != null && vm.lngDestino != null) {
        setState(() { _loadingPolyline = true; });
        try {
          final direcciones = Direcciones();
          String? polyline = await direcciones.getPolyline(
            _ubicacionConductor!.latitude,
            _ubicacionConductor!.longitude,
            vm.latDestino!,
            vm.lngDestino!
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
        setState(() { _loadingPolyline = false; });
      }
    } catch (e) {
      setState(() { _loadingUbicacion = false; });
      debugPrint('Error obteniendo ubicación: $e');
    }
  }

void _escucharMovimientoConductor() {

  final vm = Provider.of<RutaConductorViewModel>(context, listen: false);

  _positionStream = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // Actualiza cada 15 metros de movimiento
    ),
  ).listen((Position position) {

    final nuevaUbicacion =
        LatLng(position.latitude, position.longitude);

    setState(() {
      _ubicacionConductor = nuevaUbicacion;
    });

if (_mapController != null &&
    _polylinePoints.isNotEmpty) {

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
        tilt: 45,
        bearing: _bearing,
      ),
        ),
      );
    }

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

    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null || vm.latDestino == null || vm.lngDestino == null) return;
    final destino = LatLng(vm.latDestino!, vm.lngDestino!);
    final bounds = LatLngBounds(
      southwest: LatLng(
        Math.min(_ubicacionConductor!.latitude, destino.latitude),
        Math.min(_ubicacionConductor!.longitude, destino.longitude),
      ),
      northeast: LatLng(
        Math.max(_ubicacionConductor!.latitude, destino.latitude),
        Math.max(_ubicacionConductor!.longitude, destino.longitude),
      ),
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );

  }

  void _sendMessage(RutaConductorViewModel vm) {

    final texto = _chatController.text.trim();

    if (texto.isEmpty) return;

    vm.enviarMensaje(
        widget.idSolicitud,
        vm.conductorId ?? '',
        texto);

    _chatController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {

      if (_chatScrollController.hasClients) {

        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );

      }

    });

  }
  // Calcula la distancia en kilómetros entre conductor y destino
  String _distanciaKmConductorDestino() {
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null || vm.latDestino == null || vm.lngDestino == null) {
      return "--";
    }
    final double distanciaMetros = Geolocator.distanceBetween(
      _ubicacionConductor!.latitude,
      _ubicacionConductor!.longitude,
      vm.latDestino!,
      vm.lngDestino!,
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
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null || vm.latDestino == null || vm.lngDestino == null) {
      return "Tiempo estimado: --";
    }
    final double distancia = Geolocator.distanceBetween(
      _ubicacionConductor!.latitude,
      _ubicacionConductor!.longitude,
      vm.latDestino!,
      vm.lngDestino!,
    ) / 1000.0;
    final double velocidad = 40.0;
    final double tiempoHoras = distancia / velocidad;
    final int minutos = (tiempoHoras * 60).round();
    return "Tiempo estimado: ${minutos} min";
  }


  Widget _chatSheet() {

    return Consumer<RutaConductorViewModel>(
      builder: (context, vm, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients && vm.mensajes.isNotEmpty) {
            _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
          }
        });
        return SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.60,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColores.background,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: const Text(
                          "Chat con el cliente",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColores.textPrimary),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColores.textPrimary),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 194, 189, 151),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ListView.builder(
                      controller: _chatScrollController,
                      itemCount: vm.mensajes.length,
                      itemBuilder: (context, index) {
                        final msg = vm.mensajes[index];
                        final esMio = msg.senderId == vm.conductorId;
                        return Container(
                          margin: EdgeInsets.only(
                            top: 10,
                            bottom: 10,
                            left: esMio ? 60 : 16,
                            right: esMio ? 16 : 60,
                          ),
                          child: Align(
                            alignment: esMio
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.68,
                                minWidth: 60,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                              decoration: BoxDecoration(
                                color: esMio ? AppColores.primary : Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.07),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      msg.texto,
                                      style: TextStyle(
                                        color: esMio ? Colors.black : Colors.black,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    msg.timestamp != null ? _formatHora(msg.timestamp!) : '',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColores.primary, width: 1.2),
                        ),
                        child: TextField(
                          controller: _chatController,
                          decoration: const InputDecoration(
                              hintText: "Escribe un mensaje...",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColores.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                        onPressed: () => _sendMessage(vm),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );

  }

  String _formatHora(DateTime fechaHora) {
    return '${fechaHora.hour.toString().padLeft(2, '0')}:${fechaHora.minute.toString().padLeft(2, '0')}';
  }

  Widget _mapWidget(BuildContext context) {
    final vm = Provider.of<RutaDestinoViewModel>(context);
    LatLng? destinoLatLng;
    if (vm.latDestino != null && vm.lngDestino != null) {
      destinoLatLng = LatLng(vm.latDestino!, vm.lngDestino!);
      print("✅ Ubicación destino encontrada: lat=${vm.latDestino}, lng=${vm.lngDestino}");
    } else {
      destinoLatLng = null;
      print("❌ Ubicación destino NO encontrada");
    }
    final target = _ubicacionConductor ?? destinoLatLng ?? _initialTarget;
    final markers = <Marker>{
      // Marcador del conductor
      if (_ubicacionConductor != null)
        Marker(
          markerId: const MarkerId('conductor'),
          position: _ubicacionConductor!,
          rotation: _bearing,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: 'Tú'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      // Marcador del destino
      if (destinoLatLng != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destinoLatLng,
          infoWindow: InfoWindow(
            title: vm.tituloDestino.isNotEmpty ? vm.tituloDestino : 'Destino',
            snippet: vm.direccionDestino.isNotEmpty ? vm.direccionDestino : null,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
      else if (_ubicacionConductor != null && destinoLatLng != null)
        Polyline(
          polylineId: const PolylineId('ruta_conductor_destino'),
          points: [_ubicacionConductor!, destinoLatLng],
          color: AppColores.primary,
          width: 5,
        ),
    };
    if (_polylinePoints.isEmpty) {
      print("⚠️ POLYLINE VACÍA → usando línea recta");
    } else {
      print("✅ POLYLINE DE GOOGLE DIRECTIONS");
    }
    print("📍 Puntos polyline cargados: ${_polylinePoints.length}");
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.70,
      child: Stack(
        children: [
          AppGoogleMap(
            initialTarget: target,
            initialZoom: _initialZoom,
            markers: markers,
            polylines: polylines,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              // No llamar _fitMarkers aquí, se llama tras obtener ubicación
            },
          ),
          if (_loadingUbicacion || _loadingPolyline)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow() {

    final vm = Provider.of<RutaDestinoViewModel>(context);

    // Calcular mensajes pendientes (no leídos) usando readBy
    final conductorId = vm.conductorId ?? '';
    final mensajesPendientes = vm.mensajes.where((m) =>
      m.senderId != conductorId &&
      (!(m.readBy[conductorId] ?? false))
    ).length;
    return Container(
      decoration: BoxDecoration(
        color: AppColores.background, // Light background color
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, color: AppColores.primary, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Ruta al destino',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColores.primary,
                  backgroundImage: vm.fotoCliente.isNotEmpty
                      ? CachedNetworkImageProvider(vm.fotoCliente)
                      : null,
                  child: vm.fotoCliente.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.nombreCliente.isNotEmpty
                            ? vm.nombreCliente.substring(0, 1).toUpperCase() + vm.nombreCliente.substring(1).toLowerCase()
                          : "Cliente",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vm.direccionDestino,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }

  Widget _bottomButtons() {

    bool _terminarViajePressed = false;
    return SafeArea(
      child: Container(
        color: AppColores.background,
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColores.primary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: AppColores.background,
                  ),
                  onPressed: () async {
                    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
                    if (_ubicacionConductor != null && vm.latDestino != null && vm.lngDestino != null) {
                      final origen = '${_ubicacionConductor!.latitude},${_ubicacionConductor!.longitude}';
                      final destino = '${vm.latDestino},${vm.lngDestino}';
                      final url = 'https://www.google.com/maps/dir/?api=1&origin=$origen&destination=$destino&travelmode=driving';
                      try {
                        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      } catch (e) {
                        debugPrint('No se pudo abrir Google Maps: $e');
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ubicación no disponible')),
                      );
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map, color: AppColores.primary),
                      const SizedBox(width: 8),
                      Text(
                        "Mapa",
                        style: TextStyle(
                          color: AppColores.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                      ),
                      onPressed: _terminarViajePressed
                          ? null
                          : () async {
                              setState(() {
                                _terminarViajePressed = true;
                              });
                              try {
                                await FirebaseFirestore.instance
                                    .collection('solicitudes')
                                    .doc(widget.idSolicitud)
                                    .update({'estado': 'completado'});
                                await RutaDestinoViewModel.mostrarNotificacion(
                                  'Viaje terminado',
                                  'El viaje ha finalizado correctamente.'
                                );
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const LoaderSolicitudCompletada(),
                                );
                                await Future.delayed(const Duration(seconds: 2));
                                Navigator.of(context).pop();
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => ResumenConductorView(solicitudId: widget.idSolicitud),
                                  ),
                                );
                              } catch (e) {
                                debugPrint('Error al cambiar estado: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('No se pudo cambiar el estado')),
                                );
                                setState(() {
                                  _terminarViajePressed = false;
                                });
                              }
                            },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            "Terminar viaje",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(0),
        child: Container(),
      ),
      body: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              // Mapa ocupa el 60% de la pantalla
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.60,
                child: _mapWidget(context),
              ),
              // Info del cliente ocupa el 20%
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.20,
                child: _infoRow(),
              ),
              // Botones ocupan el resto
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _bottomButtons(),
                ),
              ),
            ],
          ),
          // Posiciona el tiempo estimado de llegada encima del mapa
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
          // Botón flotante abajo a la izquierda del mapa: muestra kilómetros
          Positioned(
            left: 24,
            bottom: MediaQuery.of(context).size.height * 0.38,
            child: FloatingActionButton.extended(
              heroTag: "fab_distancia",
              backgroundColor: Colors.white,
              icon: const Icon(Icons.directions_car, color: Colors.black),
              label: Text(
                _distanciaKmConductorDestino(),
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
          // Posiciona el botón flotante abajo a la derecha del mapa
          Positioned(
            right: 24,
            bottom: MediaQuery.of(context).size.height * 0.38, // Siempre encima del mapa
            child: FloatingActionButton(
              heroTag: "fab_centrar",
              backgroundColor: AppColores.buttonPrimary,
              child: Icon(_centraSoloConductor
                  ? Icons.person_pin_circle
                  : Icons.group),
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
          
        ],
      ),
    );
  

  }
  
}