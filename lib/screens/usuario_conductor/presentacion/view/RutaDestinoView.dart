import 'dart:async';
import 'dart:math' as Math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaDestinoViewModel.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/firebase_service.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class RutaDestino extends StatelessWidget {
  final String idSolicitud;

  const RutaDestino({super.key, required this.idSolicitud});

  @override
  Widget build(BuildContext context) {
    var hasProvider = true;
    try {
      Provider.of<RutaDestinoViewModel>(context, listen: false);
    } catch (_) {
      hasProvider = false;
    }

    if (hasProvider) {
      return _RutaDestinoContent(idSolicitud: idSolicitud);
    }

    return ChangeNotifierProvider<RutaDestinoViewModel>(
      create: (_) => RutaDestinoViewModel(),
      child: _RutaDestinoContent(idSolicitud: idSolicitud),
    );
  }
}

class _RutaDestinoContent extends StatefulWidget {
  final String idSolicitud;

  const _RutaDestinoContent({super.key, required this.idSolicitud});

  @override
  State<_RutaDestinoContent> createState() => _RutaDestinoContentState();
}

class _RutaDestinoContentState extends State<_RutaDestinoContent> with WidgetsBindingObserver {
  static const SystemUiOverlayStyle _rutaDestinoOverlayStyle =
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.white,
        systemNavigationBarContrastEnforced: false,
      );

  bool _isPaused = false;
  bool _completionFlowInProgress = false;
  bool _terminarViajePressed = false;
  bool _backgroundServiceRunning = false;
  bool _backgroundServiceStarting = false;
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
      if (!mounted) return;

      final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
      // Guardar el idSolicitud en cache al ingresar a la clase
      await vm.guardarSolicitudActiva(widget.idSolicitud);
      if (!mounted) return;

      // Persistir que estamos en la pantalla de ruta conductor para restaurar en reload
      try {
        await SessionHelper.setActiveSolicitudScreen('ruta_destino');
      } catch (_) {}
      if (!mounted) return;

      await vm.cargarDatosCliente(widget.idSolicitud);
      if (!mounted) return;

      await _cargarMarcadoresPersonalizados();
      if (!mounted) return;

      vm.iniciarChat(widget.idSolicitud);
      if (!mounted) return;

      vm.escucharEstadoSolicitud(
        widget.idSolicitud,
        onSolicitudCompletada: _onSolicitudCompletada,
      );
      if (!mounted) return;

      await _obtenerUbicacionConductor();
      if (!mounted) return;

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
    // Ensure background service is stopped when widget is disposed
    try {
      _detenerTrackingBackground();
    } catch (_) {}
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
    if (_backgroundServiceRunning || _backgroundServiceStarting) return;
    _backgroundServiceStarting = true;
    try {
      debugPrint('🚀 [LOG] Iniciando tracking background desde onPaused');
      await initializeBackgroundService();
      await startBackgroundTrackingService();
      final service = FlutterBackgroundService();

      // Give the isolate a short moment to register listeners before sending the command.
      await Future<void>.delayed(const Duration(milliseconds: 450));

      final uid = FirebaseAuth.instance.currentUser?.uid;
      service.invoke('startTracking', {
        'userId': uid,
        'userType': 'conductor',
        'solicitudId': widget.idSolicitud,
      });

      _backgroundServiceRunning = true;
      debugPrint('✅ [LOG] Background service iniciado');
    } catch (e) {
      _backgroundServiceRunning = false;
      debugPrint('Error iniciando tracking background: $e');
    } finally {
      _backgroundServiceStarting = false;
    }
  }

  // Verifica en modo debug que la ubicacion fue persistida correctamente.
  Future<void> _verifyUbicacionPersistida(LatLng loc) async {
    if (!kDebugMode) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.idSolicitud)
          .get();
      final data = doc.data();
      final storedLat = (data?['conductor']?['ubicacion']?['lat']);
      final storedLng = (data?['conductor']?['ubicacion']?['lng']);
      debugPrint('[VERIFY] Solicitud ${widget.idSolicitud} storedLat=$storedLat storedLng=$storedLng expectedLat=${loc.latitude} expectedLng=${loc.longitude}');
      if (storedLat == null || storedLng == null) {
        debugPrint('[VERIFY][ERROR] ubicacion no encontrada en documento');
        return;
      }
      final double lat = (storedLat as num).toDouble();
      final double lng = (storedLng as num).toDouble();
      final latDiff = (lat - loc.latitude).abs();
      final lngDiff = (lng - loc.longitude).abs();
      if (latDiff > 0.0005 || lngDiff > 0.0005) {
        debugPrint('[VERIFY][WARN] Diferencia significativa entre escrito y leído (latDiff=$latDiff, lngDiff=$lngDiff)');
      } else {
        debugPrint('[VERIFY][OK] Ubicación persistida correctamente');
      }
    } catch (e) {
      debugPrint('[VERIFY][ERROR] Error leyendo doc para verificación: $e');
    }
  }

  Future<void> _detenerTrackingBackground() async {
    if (!_backgroundServiceRunning && !_backgroundServiceStarting) return;
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
      _backgroundServiceRunning = false;
      debugPrint('🛑 [LOG] Background service detenido');
    } catch (e) {
      debugPrint('Error deteniendo background service: $e');
    } finally {
      _backgroundServiceStarting = false;
      _backgroundServiceRunning = false;
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
      try {
        final svc = TripTrackingFirebaseService();
        final ts = DateTime.now().millisecondsSinceEpoch;
        await svc.actualizarUbicacionConductorEnSolicitud(
          solicitudId: widget.idSolicitud,
          location: nuevaUbicacion,
          timestampMs: ts,
          appendRouteHistory: true,
        );
        debugPrint(
          '[LOG] Ubicación guardada en Firestore (servicio): lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}',
        );
        await _verifyUbicacionPersistida(nuevaUbicacion);
      } catch (e) {
        debugPrint('Error guardando ubicación (servicio): $e');
      }
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
        if (!mounted) return;
        setState(() {
          _loadingPolyline = true;
        });
        try {
          final mapService = const MapService();
          final points = await mapService.getRoutePolyline(
            _ubicacionConductor!,
            LatLng(vm.latDestino!, vm.lngDestino!),
          );
          if (points.isNotEmpty) {
            _polylinePoints = points;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUbicacion = false;
        });
      }
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
            final timestampMs = DateTime.now().millisecondsSinceEpoch;
            final svc = TripTrackingFirebaseService();
            await svc.actualizarUbicacionConductorEnSolicitud(
              solicitudId: widget.idSolicitud,
              location: nuevaUbicacion,
              timestampMs: timestampMs,
              appendRouteHistory: true,
            );
            debugPrint(
              '[LOG] Ubicación guardada en base de datos (servicio): lat=${nuevaUbicacion.latitude}, lng=${nuevaUbicacion.longitude}, ts=$timestampMs',
            );
            await _verifyUbicacionPersistida(nuevaUbicacion);
          } catch (e) {
            debugPrint('Error guardando ubicación obtenida (servicio): $e');
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
      // Ensure background tracking is stopped when finalizing the trip
      try {
        await _detenerTrackingBackground();
      } catch (_) {}

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
      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) =>
            ResumenConductorView(solicitudId: widget.idSolicitud),
        delay: const Duration(milliseconds: 1400),
        title: 'Viaje finalizado',
        subtitle: 'Generando resumen del servicio...',
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
        final mapService = const MapService();
        final points = await mapService.getRoutePolyline(
          _ubicacionConductor!,
          LatLng(vm.latDestino!, vm.lngDestino!),
        );
        if (points.isNotEmpty) {
          _polylinePoints = points;
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

  // Calcula la distancia real hacia el destino en metros.
  // Si existe una polyline (ruta) usa la suma de segmentos, sino usa la distancia en línea recta.
  double? _distanceMetersToDestino() {
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null || vm.latDestino == null || vm.lngDestino == null) {
      return null;
    }

    if (_polylinePoints.isNotEmpty) {
      double total = 0.0;
      for (int i = 0; i < _polylinePoints.length - 1; i++) {
        final a = _polylinePoints[i];
        final b = _polylinePoints[i + 1];
        total += Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
      }
      // If polyline somehow gave zero, fallback to straight-line
      if (total <= 0) {
        final destLat = vm.latDestino!;
        final destLng = vm.lngDestino!;
        return Geolocator.distanceBetween(_ubicacionConductor!.latitude, _ubicacionConductor!.longitude, destLat, destLng);
      }
      return total;
    }

    final destLat = vm.latDestino!;
    final destLng = vm.lngDestino!;
    return Geolocator.distanceBetween(_ubicacionConductor!.latitude, _ubicacionConductor!.longitude, destLat, destLng);
  }

  // Calcula la distancia en kilómetros entre conductor y destino
  String _distanciaKmConductorDestino() {
    final meters = _distanceMetersToDestino();
    if (meters == null) return "--";
    if (meters < 1000) {
      return "${meters.round()} m";
    } else {
      final double distanciaKm = meters / 1000.0;
      return "${distanciaKm.toStringAsFixed(2)} km";
    }
  }

  // Calcula el tiempo estimado de llegada
  String _tiempoEstimadoLlegada() {
    final meters = _distanceMetersToDestino();
    if (meters == null) return "Tiempo estimado: --";
    final double distanciaKm = meters / 1000.0;
    // velocidad media estimada en km/h
    final double velocidad = 40.0;
    final double tiempoHoras = distanciaKm / velocidad;
    final int minutos = (tiempoHoras * 60).round();
    return "Tiempo estimado: ${minutos} min";
  }

  Widget _mapWidget(BuildContext context) {
    final vm = Provider.of<RutaDestinoViewModel>(context);
    LatLng? destinoLatLng;
    if (vm.latDestino != null && vm.lngDestino != null) {
      destinoLatLng = LatLng(vm.latDestino!, vm.lngDestino!);
      debugPrint(
        "✅ Ubicación destino encontrada: lat=${vm.latDestino}, lng=${vm.lngDestino}",
      );
    } else {
      destinoLatLng = null;
      debugPrint("❌ Ubicación destino NO encontrada");
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
      debugPrint("⚠️ POLYLINE VACÍA → usando línea recta");
    } else {
      debugPrint("✅ POLYLINE DE GOOGLE DIRECTIONS");
    }
    debugPrint("📍 Puntos polyline cargados: ${_polylinePoints.length}");
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
            radius: 45,
            backgroundColor: AppColores.primary,
            backgroundImage: vm.fotoCliente.isNotEmpty
                ? CachedNetworkImageProvider(vm.fotoCliente)
                : null,
            child: vm.fotoCliente.isEmpty
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenW = constraints.maxWidth;
                    double nameFont = 30;
                    double addressFont = 20;
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
            // Posiciona la tarjeta con tiempo y distancia encima del mapa (estilo referencia)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.amber, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _tiempoEstimadoLlegada().replaceFirst('Tiempo estimado: ', ''),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        height: 28,
                        width: 1,
                        color: Colors.grey.shade300,
                      ),
                      Row(
                        children: [
                          const Icon(Icons.route, color: Colors.black54, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _distanciaKmConductorDestino(),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
