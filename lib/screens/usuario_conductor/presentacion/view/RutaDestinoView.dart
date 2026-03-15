import 'dart:async';
import 'dart:math' as Math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaDestinoViewModel.dart';
import 'package:taxi_app/services/DireccionesServicio.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/widgets/LoaderCompletado.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class RutaDestino extends StatefulWidget {
  final String idSolicitud;

  const RutaDestino({super.key, required this.idSolicitud});

  @override
  State<RutaDestino> createState() => _RutaDestinoState();
}

class _RutaDestinoState extends State<RutaDestino> with WidgetsBindingObserver {
  static const SystemUiOverlayStyle _rutaDestinoOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.white,
        systemNavigationBarContrastEnforced: false,
      );

  bool _isPaused = false;
  bool _completionFlowInProgress = false;
  bool _terminarViajePressed = false;
  // El servicio background ahora se inicia solo desde el ViewModel y solo si no está corriendo

  GoogleMapController? _mapController;

  LatLng? _ubicacionConductor;
  bool _loadingUbicacion = true;

  StreamSubscription<Position>? _positionStream;

  bool _centraSoloConductor = true;

  final LatLng _initialTarget = LatLng(8.2595534, -73.353469);
  final double _initialZoom = 15.0;

  final Set<Circle> _circles = {};

  List<LatLng> _polylinePoints = [];
  bool _loadingPolyline = false;
  LatLng? _ubicacionInicialConductor;
  BitmapDescriptor? _destinoMarkerIcon;
  // Calcula los bounds de la polyline para ajustar la cámara
  LatLngBounds? _calcularBoundsPolyline(List<LatLng> points) {
    if (points.isEmpty) return null;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_rutaDestinoOverlayStyle);
    // Inicializa notificaciones locales
    RutaDestinoViewModel.inicializarNotificaciones();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RutaDestinoViewModel.mostrarNotificacion(
        'Continúa el servicio',
        'Lleva el cliente a su destino.',
      );
      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      // Guardar el idSolicitud en cache al ingresar a la clase
      await vm.guardarSolicitudActiva(widget.idSolicitud);
      await vm.cargarDatosCliente(widget.idSolicitud);
      await _cargarMarcadoresPersonalizados();
      vm.iniciarChat(widget.idSolicitud);
      vm.escucharEstadoSolicitud(
        widget.idSolicitud,
        onSolicitudCompletada: _onSolicitudCompletada,
      );
      await _obtenerUbicacionConductor();
      // Inicia tracking de ubicación en background
      await vm.iniciarTrackingUbicacion(widget.idSolicitud);
    });
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final destinoIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_red.png',
      size: const Size(106, 106),
    );
    if (!mounted) return;
    setState(() {
      _destinoMarkerIcon = destinoIcon;
    });
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
    if (state == AppLifecycleState.paused) {
      debugPrint(
        '🚀 [LOG] RutaDestinoView: onPaused - iniciando background service',
      );
      _isPaused = true;
      _iniciarTrackingBackground();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint(
        '🚀 [LOG] RutaDestinoView: onResumed - deteniendo background service',
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_rutaDestinoOverlayStyle);
      _isPaused = false;
      _detenerTrackingBackground();
    }
  }

  Future<void> _iniciarTrackingBackground() async {
    try {
      debugPrint('🚀 [LOG] Iniciando tracking background desde onPaused');
      await initializeBackgroundService();
      await startBackgroundTrackingService();
      debugPrint('✅ [LOG] Background service iniciado');
    } catch (e) {
      debugPrint('Error iniciando tracking background: $e');
    }
  }

  Future<void> _detenerTrackingBackground() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke("stop");
      debugPrint('🛑 [LOG] Background service detenido');
    } catch (e) {
      debugPrint('Error deteniendo background service: $e');
    }
  }

  Future<void> _obtenerUbicacionConductor() async {
    setState(() {
      _loadingUbicacion = true;
    });
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final nuevaUbicacion = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _ubicacionConductor = nuevaUbicacion;
        _loadingUbicacion = false;
        if (_ubicacionInicialConductor == null) {
          _ubicacionInicialConductor = _ubicacionConductor;
        }
      });
      // Actualizar en Firestore (solicitudes -> conductor -> ubicacion)
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.idSolicitud)
          .update({
            'conductor.ubicacion': {
              'lat': nuevaUbicacion.latitude,
              'lng': nuevaUbicacion.longitude,
            },
          });
      debugPrint(
        '[LOG] Ubicación guardada en Firestore: lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}',
      );
      if (!mounted) return;
      setState(() {});
      // Centrar ambos marcadores y ajustar zoom
      _fitMarkers();

      _escucharMovimientoConductor();

      // Obtener polyline de Google Directions API
      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      if (_ubicacionConductor != null &&
          vm.latDestino != null &&
          vm.lngDestino != null) {
        setState(() {
          _loadingPolyline = true;
        });
        try {
          final direcciones = Direcciones();
          String? polyline = await direcciones.getPolyline(
            _ubicacionConductor!.latitude,
            _ubicacionConductor!.longitude,
            vm.latDestino!,
            vm.lngDestino!,
          );
          if (polyline != null && polyline.isNotEmpty) {
            _polylinePoints = _decodePolyline(polyline);
            // Ajusta la cámara para mostrar la polyline completa
            if (_mapController != null && _polylinePoints.isNotEmpty) {
              final bounds = _calcularBoundsPolyline(_polylinePoints);
              if (bounds != null) {
                await _mapController!.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, 80),
                );
              }
            }
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
      }
    } catch (e) {
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
            distanceFilter: 15, // Actualiza cada 15 metros de movimiento
          ),
        ).listen((Position position) async {
          final nuevaUbicacion = LatLng(position.latitude, position.longitude);

          if (!mounted) return;
          setState(() {
            _ubicacionConductor = nuevaUbicacion;
          });

          debugPrint(
            '[LOG] Ubicación extraída del GPS: lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}',
          );
          if (_isPaused) {
            debugPrint(
              '[LOG] [onPaused] Ubicación obtenida: lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}',
            );
          }

          // Guardar ubicación obtenida y fecha en Firestore (igual que en RutaConductorView)
          try {
            final fechaEnvio = DateTime.now().toIso8601String();
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
            debugPrint(
              '[LOG] Ubicación guardada en base de datos: lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}, fecha=$fechaEnvio',
            );
          } catch (e) {
            debugPrint('Error guardando ubicación obtenida: $e');
          }

          // Ajusta la cámara para mostrar la polyline completa al mover el conductor
          if (_mapController != null && _polylinePoints.isNotEmpty) {
            final bounds = _calcularBoundsPolyline(_polylinePoints);
            if (bounds != null && mounted) {
              _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 80),
              );
            }
          }

          // Si el conductor se desvía más de 50 metros de la polyline, solicita nueva ruta
          if (_polylinePoints.isNotEmpty && _ubicacionConductor != null) {
            double minDist = double.infinity;
            for (final p in _polylinePoints) {
              final dist = Geolocator.distanceBetween(
                _ubicacionConductor!.latitude,
                _ubicacionConductor!.longitude,
                p.latitude,
                p.longitude,
              );
              if (dist < minDist) minDist = dist;
            }
            if (minDist > 50) {
              _solicitarNuevaPolyline();
            }
          }
        });
  }

  Future<void> _onSolicitudCompletada() async {
    await _finalizarFlujoViaje(actualizarEstadoSolicitud: false);
  }

  Future<void> _finalizarFlujoViaje({
    required bool actualizarEstadoSolicitud,
  }) async {
    if (_completionFlowInProgress || !mounted) return;

    setState(() {
      _completionFlowInProgress = true;
      _terminarViajePressed = true;
    });

    try {
      if (actualizarEstadoSolicitud) {
        final fechaHoraFinalizacion = DateTime.now();
        await FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(widget.idSolicitud)
            .update({
              'estado': 'completado',
              'fecha de terminacion': fechaHoraFinalizacion,
            });
      }

      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      await vm.finalizarSolicitud(widget.idSolicitud);
      await RutaDestinoViewModel.mostrarNotificacion(
        'Viaje terminado',
        'El viaje ha finalizado correctamente.',
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoaderSolicitudCompletada(),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResumenConductorView(solicitudId: widget.idSolicitud),
        ),
      );
    } catch (e) {
      debugPrint('Error finalizando viaje: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo finalizar el viaje')),
        );
        setState(() {
          _completionFlowInProgress = false;
          _terminarViajePressed = false;
        });
      }
    }
  }

  Future<void> _solicitarNuevaPolyline() async {
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor != null &&
        vm.latDestino != null &&
        vm.lngDestino != null) {
      if (!mounted) return;
      setState(() {
        _loadingPolyline = true;
      });
      try {
        final direcciones = Direcciones();
        String? polyline = await direcciones.getPolyline(
          _ubicacionConductor!.latitude,
          _ubicacionConductor!.longitude,
          vm.latDestino!,
          vm.lngDestino!,
        );
        if (polyline != null && polyline.isNotEmpty) {
          _polylinePoints = _decodePolyline(polyline);
          // Ajusta la cámara para mostrar la polyline completa
          if (_mapController != null && _polylinePoints.isNotEmpty) {
            final bounds = _calcularBoundsPolyline(_polylinePoints);
            if (bounds != null) {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 80),
              );
            }
          }
        } else {
          _polylinePoints = [];
        }
      } catch (e) {
        _polylinePoints = [];
        debugPrint('Error obteniendo polyline: $e');
      }
      if (!mounted) return;
      setState(() {
        _loadingPolyline = false;
      });
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
    if (_ubicacionConductor == null ||
        vm.latDestino == null ||
        vm.lngDestino == null)
      return;
    final destino = LatLng(vm.latDestino!, vm.lngDestino!);
    // Centrar ambos marcadores usando bounds
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
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  // Calcula la distancia en kilómetros entre conductor y destino
  String _distanciaKmConductorDestino() {
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null ||
        vm.latDestino == null ||
        vm.lngDestino == null) {
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
    if (_ubicacionConductor == null ||
        vm.latDestino == null ||
        vm.lngDestino == null) {
      return "Tiempo estimado: --";
    }
    final double distancia =
        Geolocator.distanceBetween(
          _ubicacionConductor!.latitude,
          _ubicacionConductor!.longitude,
          vm.latDestino!,
          vm.lngDestino!,
        ) /
        1000.0;
    final double velocidad = 40.0;
    final double tiempoHoras = distancia / velocidad;
    final int minutos = (tiempoHoras * 60).round();
    return "Tiempo estimado: ${minutos} min";
  }

  Widget _mapWidget(BuildContext context) {
    final vm = Provider.of<RutaDestinoViewModel>(context);
    LatLng? destinoLatLng;
    if (vm.latDestino != null && vm.lngDestino != null) {
      destinoLatLng = LatLng(vm.latDestino!, vm.lngDestino!);
      print(
        "✅ Ubicación destino encontrada: lat=${vm.latDestino}, lng=${vm.lngDestino}",
      );
    } else {
      destinoLatLng = null;
      print("❌ Ubicación destino NO encontrada");
    }
    final target = _ubicacionConductor ?? destinoLatLng ?? _initialTarget;
    final markers = <Marker>{
      // // Marcador del conductor
      // if (_ubicacionConductor != null)
      //   Marker(
      //     markerId: const MarkerId('conductor'),
      //     position: _ubicacionConductor!,
      //     rotation: _bearing,
      //     anchor: const Offset(0.5, 0.5),
      //     flat: true,
      //     infoWindow: const InfoWindow(title: 'Tú'),
      //     icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      //   ),
      // Marcador del destino
      if (destinoLatLng != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destinoLatLng,
          infoWindow: InfoWindow(
            title: vm.tituloDestino.isNotEmpty ? vm.tituloDestino : 'Destino',
            snippet: vm.direccionDestino.isNotEmpty
                ? vm.direccionDestino
                : null,
          ),
          icon:
              _destinoMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
    final vm = Provider.of<RutaDestinoViewModel>(context);
    return Padding(
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
                              ? vm.nombreCliente.substring(0, 1).toUpperCase() +
                                    vm.nombreCliente.substring(1).toLowerCase()
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
                          vm.direccionDestino,
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
          // Stack(
          //   children: [
          //     IconButton(
          //       icon: Image.asset(
          //         'assets/img/icon_location.png',
          //         width: 40,
          //         height: 40,
          //       ),
          //       onPressed: () async {
          //         for (final m in vm.mensajes) {
          //           if (m.senderId != conductorId && !(m.readBy[conductorId] ?? false)) {
          //             await vm.chatService.markMessageRead(
          //               solicitudId: widget.idSolicitud,
          //               messageId: m.id,
          //               userId: conductorId,
          //             );
          //           }
          //         }
          //         if (_ubicacionConductor != null && vm.latDestino != null && vm.lngDestino != null) {
          //           final origen = '${_ubicacionConductor!.latitude},${_ubicacionConductor!.longitude}';
          //           final destino = '${vm.latDestino},${vm.lngDestino}';
          //           final url = 'https://www.google.com/maps/dir/?api=1&origin=$origen&destination=$destino&travelmode=driving';
          //           try {
          //             await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          //           } catch (e) {
          //             debugPrint('No se pudo abrir Google Maps: $e');
          //           }
          //         } else {
          //           ScaffoldMessenger.of(context).showSnackBar(
          //             SnackBar(content: Text('Ubicación no disponible')),
          //           );
          //         }
          //       },
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  Widget _bottomButtons() {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    double buttonFontSize = 18;
    double buttonPaddingV = 18;
    double buttonIconSize = 22;
    double buttonBorderRadius = 16;
    double buttonSpacing = 8;
    if (screenW >= 1000) {
      buttonFontSize = 24;
      buttonPaddingV = 28;
      buttonIconSize = 32;
      buttonBorderRadius = 24;
      buttonSpacing = 16;
    } else if (screenW < 350) {
      buttonFontSize = 14;
      buttonPaddingV = 10;
      buttonIconSize = 16;
      buttonBorderRadius = 10;
      buttonSpacing = 4;
    } else if (screenW < 500) {
      buttonFontSize = 16;
      buttonPaddingV = 14;
      buttonIconSize = 18;
      buttonBorderRadius = 12;
      buttonSpacing = 6;
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Container(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColores.primary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(buttonBorderRadius),
                    ),
                    padding: EdgeInsets.symmetric(vertical: buttonPaddingV),
                    backgroundColor: AppColores.background,
                  ),
                  onPressed: () async {
                    final vm = Provider.of<RutaDestinoViewModel>(
                      context,
                      listen: false,
                    );
                    if (_ubicacionConductor != null &&
                        vm.latDestino != null &&
                        vm.lngDestino != null) {
                      final origen =
                          '${_ubicacionConductor!.latitude},${_ubicacionConductor!.longitude}';
                      final destino = '${vm.latDestino},${vm.lngDestino}';
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map,
                        color: AppColores.primary,
                        size: buttonIconSize,
                      ),
                      SizedBox(width: buttonSpacing),
                      Flexible(
                        child: Text(
                          "Mapa",
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
              ),
              SizedBox(
                width: screenW >= 1000
                    ? 32
                    : screenW < 350
                    ? 8
                    : 20,
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            buttonBorderRadius,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(vertical: buttonPaddingV),
                        elevation: 0,
                      ),
                      onPressed: _terminarViajePressed
                          ? null
                          : () async {
                              await _finalizarFlujoViaje(
                                actualizarEstadoSolicitud: true,
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
                          SizedBox(width: buttonSpacing),
                          Flexible(
                            child: Text(
                              "Terminar viaje",
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _rutaDestinoOverlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        backgroundColor: AppColores.background,
        body: Stack(
          children: [
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
                                  "Ruta al Destino",
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
            // Posiciona el tiempo estimado de llegada encima del mapa
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
            // Botón flotante abajo a la izquierda del mapa: muestra kilómetros
            Positioned(
              left: 24,
              bottom: MediaQuery.of(context).size.height * 0.35,
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
              bottom:
                  MediaQuery.of(context).size.height *
                  0.35, // Siempre encima del mapa
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
          ],
        ),
      ),
    );
  }
}
