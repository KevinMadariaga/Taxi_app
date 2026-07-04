import 'dart:async';
import 'dart:math' as Math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/RutaDestinoViewModel.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/features/driver_trip/widgets/driver_client_info_card.dart';
import 'package:taxi_app/features/driver_trip/screens/reportar_problema_screen.dart';

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

  const _RutaDestinoContent({required this.idSolicitud});

  @override
  State<_RutaDestinoContent> createState() => _RutaDestinoContentState();
}

class _RutaDestinoContentState extends State<_RutaDestinoContent>
    with WidgetsBindingObserver {
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

  LatLng? _ubicacionInicialConductor;
  BitmapDescriptor? _destinoMarkerIcon;
  BitmapDescriptor? _conductorMarkerIcon;

  // Smooth animation
  bool _isMoto = false;
  LatLng? _conductorSmooth;
  LatLng? _conductorTarget;
  double _conductorRotation = 0;
  Timer? _movementTimer;
  int _cameraFollowTick = 0;
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

      await _loadTipoVehiculo();
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

  Future<void> _loadTipoVehiculo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.idSolicitud)
          .get();
      final tipo = (doc.data()?['tipoVehiculo'] ?? '').toString().toLowerCase();
      if (mounted) setState(() => _isMoto = tipo == 'moto');
    } catch (_) {}
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final dpr = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .devicePixelRatio;
    final destinoIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_red.png',
      size: const Size(48, 48),
      devicePixelRatio: dpr,
    );
    if (!mounted) return;
    setState(() {
      _destinoMarkerIcon = destinoIcon;
      // _conductorMarkerIcon queda null → usa el marcador azul default del mapa
    });
  }

  void _enqueueSmoothTarget(LatLng newPos, double? heading) {
    _conductorTarget = newPos;
    if (heading != null) {
      _conductorRotation = _lerpAngle(_conductorRotation, heading, 0.3);
    }
    _ensureMovementTimer();
  }

  void _ensureMovementTimer() {
    _movementTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      _tickMovement,
    );
  }

  void _tickMovement(Timer _) {
    if (!mounted) {
      _movementTimer?.cancel();
      _movementTimer = null;
      return;
    }
    final target = _conductorTarget;
    if (target == null) return;
    if (_conductorSmooth == null) {
      setState(() => _conductorSmooth = target);
      return;
    }
    const alpha = 0.15;
    final newLat = _conductorSmooth!.latitude +
        (target.latitude - _conductorSmooth!.latitude) * alpha;
    final newLng = _conductorSmooth!.longitude +
        (target.longitude - _conductorSmooth!.longitude) * alpha;
    final dist = Geolocator.distanceBetween(
      newLat, newLng, target.latitude, target.longitude,
    );
    final current = dist < 0.3 ? target : LatLng(newLat, newLng);
    setState(() {
      _conductorSmooth = current;
    });

    // Cámara de navegación (estilo Google Maps al "iniciar ruta"): sigue al
    // conductor centrado, con la vista rotada según el rumbo de avance (así
    // se nota "coger la curva" al girar) y un tilt 3D en vez de plano cenital.
    // Cada 10 ticks (~500ms): el costo real no es el tilt/rotación en sí
    // (el SDK nativo ya está optimizado para eso, es lo mismo que hace la
    // navegación real de Google Maps) sino la frecuencia de animateCamera —
    // a más de ~2/seg empieza a notarse en Android de gama baja.
    _cameraFollowTick++;
    if (_cameraFollowTick >= 10 && _centraSoloConductor && _mapController != null) {
      _cameraFollowTick = 0;
      unawaited(
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: current,
              bearing: _conductorRotation,
              zoom: 17.5,
            ),
          ),
        ),
      );
    }
  }

  double _lerpAngle(double current, double target, double t) {
    final diff = (target - current + 540) % 360 - 180;
    return (current + diff * t) % 360;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _movementTimer?.cancel();
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
      _iniciarTrackingBackground();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint(
        '🚀 [LOG] RutaDestinoView: onResumed - deteniendo background service',
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_rutaDestinoOverlayStyle);
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
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
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
        await vm.verificarUbicacionPersistida(widget.idSolicitud, nuevaUbicacion);
      } catch (e) {
        debugPrint('Error guardando ubicación (servicio): $e');
      }
      if (!mounted) return;
      setState(() {});
      // Centrar ambos marcadores y ajustar zoom
      _fitMarkers();

      _escucharMovimientoConductor();

      // Obtener polyline de Google Directions API
      if (_ubicacionConductor != null &&
          vm.latDestino != null &&
          vm.lngDestino != null) {
        if (!mounted) return;
        try {
          await vm.fetchRoute(
            _ubicacionConductor!,
            LatLng(vm.latDestino!, vm.lngDestino!),
          );
          if (vm.routePoints.isNotEmpty) {
            // Ajusta la cámara para mostrar la polyline completa
            if (_mapController != null) {
              final bounds = _calcularBoundsPolyline(vm.routePoints);
              if (bounds != null) {
                await _mapController!.animateCamera(
                  CameraUpdate.newLatLngBounds(bounds, 80),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Error obteniendo polyline: $e');
        }
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
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) async {
          final nuevaUbicacion = LatLng(position.latitude, position.longitude);

          if (!mounted) return;
          setState(() => _ubicacionConductor = nuevaUbicacion);
          _enqueueSmoothTarget(nuevaUbicacion, position.heading);

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
            await vm.verificarUbicacionPersistida(widget.idSolicitud, nuevaUbicacion);
          } catch (e) {
            debugPrint('Error guardando ubicación obtenida (servicio): $e');
          }

          // Ajusta la cámara para mostrar perspectiva 3D
          vm.currentDriverLocation = nuevaUbicacion;
          final persp = vm.getCameraPerspective();
          if (persp != null && _mapController != null && mounted) {
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(persp),
            );
          }

          // Si el conductor se desvía más de 50 metros de la polyline, solicita nueva ruta
          if (vm.routePoints.isNotEmpty && _ubicacionConductor != null) {
            double minDist = double.infinity;
            for (final p in vm.routePoints) {
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

    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);

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
        await vm.marcarCompletado(widget.idSolicitud);
      }
      await vm.finalizarSolicitud(widget.idSolicitud);

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
      await vm.fetchRoute(
        _ubicacionConductor!,
        LatLng(vm.latDestino!, vm.lngDestino!),
      );
      _fitMarkers();
    }
  }

  void _centerOnConductor() {
    final pos = _conductorSmooth ?? _ubicacionConductor;
    if (_mapController != null && pos != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            bearing: _conductorRotation,
            zoom: 17.5,
          ),
        ),
      );
    }
  }

  Future<void> _fitMarkers() async {
    final controller = _mapController;
    if (controller == null) return;

    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null ||
        vm.latDestino == null ||
        vm.lngDestino == null) {
      return;
    }
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

    // Reset a vista cenital antes del fit: si venía del modo navegación
    // (tilt 3D + rumbo rotado), newLatLngBounds no encuadra bien con la
    // cámara todavía inclinada/rotada.
    final currentZoom = await controller.getZoomLevel();
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            (_ubicacionConductor!.latitude + destino.latitude) / 2,
            (_ubicacionConductor!.longitude + destino.longitude) / 2,
          ),
          bearing: 0,
          tilt: 0,
          zoom: currentZoom,
        ),
      ),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  // Calcula la distancia real hacia el destino en metros.
  // Si existe una polyline (ruta) usa la suma de segmentos, sino usa la distancia en línea recta.
  double? _distanceMetersToDestino() {
    final vm = Provider.of<RutaDestinoViewModel>(context, listen: false);
    if (_ubicacionConductor == null ||
        vm.latDestino == null ||
        vm.lngDestino == null) {
      return null;
    }

    if (vm.routePoints.isNotEmpty) {
      double total = 0.0;
      for (int i = 0; i < vm.routePoints.length - 1; i++) {
        final a = vm.routePoints[i];
        final b = vm.routePoints[i + 1];
        total += Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        );
      }
      // If polyline somehow gave zero, fallback to straight-line
      if (total <= 0) {
        final destLat = vm.latDestino!;
        final destLng = vm.lngDestino!;
        return Geolocator.distanceBetween(
          _ubicacionConductor!.latitude,
          _ubicacionConductor!.longitude,
          destLat,
          destLng,
        );
      }
      return total;
    }

    final destLat = vm.latDestino!;
    final destLng = vm.lngDestino!;
    return Geolocator.distanceBetween(
      _ubicacionConductor!.latitude,
      _ubicacionConductor!.longitude,
      destLat,
      destLng,
    );
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
    final destinoLatLng = (vm.latDestino != null && vm.lngDestino != null)
        ? LatLng(vm.latDestino!, vm.lngDestino!)
        : null;
    final target = _ubicacionConductor ?? destinoLatLng ?? _initialTarget;
    final markers = <Marker>{
      if (destinoLatLng != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destinoLatLng,
          infoWindow: InfoWindow(
            title: vm.tituloDestino.isNotEmpty ? vm.tituloDestino : 'Destino',
            snippet: vm.direccionDestino.isNotEmpty ? vm.direccionDestino : null,
          ),
          icon: _destinoMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
    };
    final polylines = <Polyline>{
      if (vm.routePoints.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('google_route'),
          points: vm.routePoints,
          color: AppColores.route,
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        )
      else if (_ubicacionConductor != null && destinoLatLng != null)
        Polyline(
          polylineId: const PolylineId('ruta_conductor_destino'),
          points: [_ubicacionConductor!, destinoLatLng],
          color: AppColores.route,
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Stack(
      children: [
        Mapagoogle(
          initialTarget: target,
          initialZoom: _initialZoom,
          markers: markers,
          polylines: polylines,
          circles: _circles,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          // Shift visual center down
          padding: EdgeInsets.only(top: 180.h, bottom: 20.h),
          onMapCreated: (controller) {
            _mapController = controller;
          },
        ),
        Positioned(
          top: 0.h,
          left: 0.w,
          right: 0.w,
          child: IgnorePointer(
            child: Container(
              height: MediaQuery.of(context).padding.top + 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.28), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        if (_loadingUbicacion || vm.isLoadingRoute)
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColores.primary),
                    SizedBox(height: 12.h),
                    Text(
                      'Cargando ruta...',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openDetails(RutaDestinoViewModel vm) {
    final nombre = vm.nombreCliente.isNotEmpty ? vm.nombreCliente : 'Cliente';
    final destino = vm.direccionDestino.isNotEmpty ? vm.direccionDestino : '—';
    final valor = _formatPesos(vm.valorServicio);
    final pago = _metodoPagoLabel(vm.metodoPago);
    final pagoIcon = _metodoPagoIcon(vm.metodoPago);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: AppColores.grey300,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 18.h),
                  Text(
                    'Detalles del servicio',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColores.textPrimary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  // Cliente.
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColores.primary,
                        backgroundImage: vm.fotoCliente.isNotEmpty
                            ? CachedNetworkImageProvider(vm.fotoCliente)
                            : null,
                        child: vm.fotoCliente.isEmpty
                            ? const Icon(
                                Icons.person,
                                size: 32,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cliente',
                              style: TextStyle(
                                color: AppColores.textSecondary,
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              nombre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17.sp,
                                color: AppColores.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18.h),
                  Divider(height: 1.h, color: AppColores.borderSubtle),
                  SizedBox(height: 14.h),
                  _DetalleRow(
                    icon: Icons.location_on,
                    color: AppColores.error,
                    label: 'Ubicación destino',
                    value: destino,
                  ),
                  SizedBox(height: 12.h),
                  _DetalleRow(
                    icon: Icons.attach_money_rounded,
                    color: AppColores.success,
                    label: 'Valor del servicio',
                    value: valor,
                  ),
                  SizedBox(height: 12.h),
                  _DetalleRow(
                    icon: pagoIcon,
                    color: AppColores.secondary,
                    label: 'Método de pago',
                    value: pago,
                    iconImage: vm.metodoPago.toLowerCase().contains('nequi')
                        ? 'assets/img/nequi.png'
                        : null,
                  ),
                  SizedBox(height: 24.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.grey200,
                        foregroundColor: AppColores.textPrimary,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      child: Text(
                        'Cerrar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<RutaDestinoViewModel>(context);
    final double? _metersToDestino = _distanceMetersToDestino();

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _rutaDestinoOverlayStyle,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          extendBodyBehindAppBar: true,
          backgroundColor: AppColores.background,
          body: Stack(
            children: [
              Positioned.fill(child: _mapWidget(context)),
              Positioned(
                top: 0.h,
                left: 0.w,
                right: 0.w,
                child: DriverClientInfoCard(
                  isMoto: _isMoto,
                  clientName: vm.nombreCliente.isNotEmpty
                      ? vm.nombreCliente
                      : 'Cliente',
                  clientAddress: vm.direccionDestino,
                  clientPhotoUrl: vm.fotoCliente,
                  unreadCount: 0,
                  onOpenNavigation: () async {
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
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ubicación no disponible'),
                          ),
                        );
                      }
                    }
                  },
                  onReportArrival: () async {
                    await _finalizarFlujoViaje(actualizarEstadoSolicitud: true);
                  },
                  isSendingArrival: _completionFlowInProgress,
                  isArrivalReported: _terminarViajePressed,
                  arrivalButtonEnabled:
                      !_loadingUbicacion &&
                      _metersToDestino != null &&
                      _metersToDestino <= 70,
                  etaText: _tiempoEstimadoLlegada().replaceFirst(
                    'Tiempo estimado: ',
                    '',
                  ),
                  distanceText: _distanciaKmConductorDestino(),
                  title: 'En viaje hacia el destino',
                  primaryButtonText: 'Terminar viaje',
                  primaryButtonSuccessText: 'Viaje terminado',
                  onDetails: () => _openDetails(vm),
                ),
              ),
              Positioned(
                left: 24.w,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: "fab_centrar",
                      backgroundColor: AppColores.buttonPrimary,
                      child: Icon(
                        _centraSoloConductor
                            ? Icons.person_pin_circle
                            : Icons.group,
                        color: AppColores.textWhite,
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
                    SizedBox(height: 10.h),
                    FloatingActionButton(
                      heroTag: "fab_problema",
                      backgroundColor: Colors.red.shade700,
                      child: const Icon(
                        Icons.report_problem_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReportarProblemaScreen(
                            solicitudId: widget.idSolicitud,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formatea un valor numérico como pesos (formato CO): `$12.000`.
String _formatPesos(double value) {
  final intVal = value.round();
  final s = intVal.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${intVal < 0 ? '-' : ''}\$${buf.toString()}';
}

/// Etiqueta legible del método de pago.
String _metodoPagoLabel(String metodo) {
  final m = metodo.toLowerCase();
  if (m.contains('efectivo') || m.contains('cash')) return 'Efectivo';
  if (m.contains('nequi')) return 'Nequi';
  if (m.contains('transfer') || m.contains('banco')) return 'Transferencia';
  return metodo.isEmpty ? 'No especificado' : metodo;
}

/// Icono según el método de pago.
IconData _metodoPagoIcon(String metodo) {
  final m = metodo.toLowerCase();
  if (m.contains('efectivo') || m.contains('cash')) {
    return Icons.payments_rounded;
  }
  if (m.contains('transfer') || m.contains('banco')) {
    return Icons.account_balance;
  }
  if (m.contains('nequi')) return Icons.account_balance_wallet;
  return Icons.payment;
}

/// Fila de detalle con icono en círculo, etiqueta y valor. Estilo alineado con
/// `TripDetailsSheet`.
class _DetalleRow extends StatelessWidget {
  const _DetalleRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.iconImage,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  /// Asset opcional a mostrar en vez del icono (ej. logo Nequi).
  final String? iconImage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32.w,
          height: 32.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconImage != null
                ? Colors.white
                : color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: iconImage != null
                ? Border.all(color: AppColores.borderSubtle)
                : null,
          ),
          child: iconImage != null
              ? Image.asset(
                  iconImage!,
                  width: 20.w,
                  height: 20.h,
                  errorBuilder: (_, _, _) => Icon(icon, color: color, size: 18),
                )
              : Icon(icon, color: color, size: 18),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColores.textSecondary,
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                value,
                style: TextStyle(
                  color: AppColores.textPrimary,
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
