import 'dart:async';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/features/trip_tracking_cliente/controllers/conductor_movement_simulator.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_route_math_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/user_trip_info_card.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/panic_button_fab.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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

class _RutaClienteDestinoContentState extends State<_RutaClienteDestinoContent>
    with WidgetsBindingObserver {
  // =====================
  // UI & System Styles
  // =====================
  static const SystemUiOverlayStyle _rutaClienteDestinoOverlayStyle =
      SystemUiOverlayStyle(
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
  StreamSubscription<LatLng?>? _conductorLocationSub;
  StreamSubscription? _conductorLocationFirestoreSub;

  // =====================
  // Map & Route State
  // =====================
  /// Motor compartido de animación/smoothing + snap-to-route + heading del
  /// conductor — el mismo que usa `TripTrackingViewModel`. Antes esta vista
  /// tenía su propia copia casi idéntica de este algoritmo (timer 50ms,
  /// backlog, snap-to-route, bearing) directamente en el State; ver
  /// `features/trip_tracking_cliente/controllers/conductor_movement_simulator.dart`.
  final ConductorMovementSimulator _movementEngine =
      ConductorMovementSimulator();
  final TripRouteMathService _mathService = const TripRouteMathService();

  LatLng? _conductorLatLng;
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _destinoMarkerIcon;
  double _conductorRotation = 0;
  String _distancia = '';

  // =====================
  // UI State
  // =====================
  bool _isMoto = false;
  bool _mostrarSoloDestino = false;
  bool _isUpdatingRoute = false;
  bool _hasInitialCameraApplied = false;
  DateTime? _lastRouteCalcAt;
  int _cameraFollowTick = 0;

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
    _movementEngine.onTick = _onMovementTick;
    _movementEngine.remainingRoutePointsNotifier.addListener(
      _onRemainingRouteChanged,
    );
    debugPrint(
      '[RutaClienteDestinoView] Escuchando ubicación del conductor para solicitud: ${widget.idSolicitud}',
    );
    _viewModel!.escucharUbicacionConductor(widget.idSolicitud);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await SessionHelper.setActiveSolicitud(widget.idSolicitud);
      try {
        await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino');
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'RutaClienteDestinoView');
      }
      _viewModel!.inicializarNotificaciones();
      if (!mounted) return;
      await _viewModel!.cargarDatosConductorYUbicacionDestino(
        widget.idSolicitud,
      );
      await _loadTipoVehiculo();
      await _cargarMarcadoresPersonalizados();
      _viewModel!.escucharEstadoSolicitud(widget.idSolicitud, context);

      // Calcular ruta una sola vez al inicio
      await _actualizarRuta();

      // Suscribirse a cambios en la solicitud para actualizar ubicación del conductor en tiempo real
      try {
        final svc = TripTrackingFirebaseService();
        _conductorLocationFirestoreSub = svc
            .watchSolicitudRaw(widget.idSolicitud)
            .listen((data) {
              if (!mounted) return;
              try {
                final conductor = data['conductor'];
                if (conductor is Map) {
                  final ubic = conductor['ubicacion'];
                  if (ubic is Map) {
                    final lat = (ubic['lat'] as num).toDouble();
                    final lng = (ubic['lng'] as num).toDouble();
                    final newPos = LatLng(lat, lng);
                    _enqueueConductorTarget(newPos);
                  }
                }
              } catch (e) {
                debugPrint(
                  '[RutaClienteDestino] Error procesando snapshot solicitud: $e',
                );
              }
            });
      } catch (e) {
        debugPrint(
          '[RutaClienteDestino] No se pudo subscribir a solicitud: $e',
        );
      }
    });
  }

  /// Se dispara cada 50ms mientras el motor está animando al conductor.
  /// Antes vivía inline dentro de `_tickMovement`, junto con el recálculo de
  /// la ruta restante y la etiqueta de distancia en cada tick — eso viajaba
  /// a `_onRemainingRouteChanged` (throttleado a 200ms dentro del motor), acá
  /// solo queda posición/rotación/cámara.
  void _onMovementTick() {
    if (!mounted) return;
    setState(() {
      _conductorLatLng = _movementEngine.currentPosition;
      _conductorRotation = _movementEngine.headingNotifier.value;

      _cameraFollowTick++;
      if (_cameraFollowTick >= 8 &&
          !_mostrarSoloDestino &&
          _mapController != null &&
          _conductorLatLng != null) {
        _cameraFollowTick = 0;
        unawaited(
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _conductorLatLng!,
                bearing: _conductorRotation,
                zoom: 16.5,
                tilt: 0,
              ),
            ),
          ),
        );
      }
    });
  }

  /// Ruta restante recalculada por el motor (throttleada a 200ms internamente).
  void _onRemainingRouteChanged() {
    if (!mounted) return;
    final visibleRoute = _movementEngine.remainingRoutePointsNotifier.value;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('ruta'),
          color: AppColores.route,
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          points: visibleRoute,
        ),
      };
      _distancia = _distanceToLabel(_polylineDistance(visibleRoute));
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
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'RutaClienteDestinoView');
    }
  }

  Future<void> _cargarMarcadoresPersonalizados() async {
    final dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final destinoIcon = await MarkerIconHelper.fromAsset(
      'assets/img/map_pin_red.png',
      size: const Size(48, 48),
      devicePixelRatio: dpr,
    );
    if (!mounted) return;
    setState(() {
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
      if (conductorLatLng != null) {
        _enqueueConductorTarget(conductorLatLng);
      }

      if (puntos.isEmpty) {
        // Mantener la ultima ruta valida evita saltos visuales cuando la API
        // devuelve vacio temporalmente: no tocar `_polylines`/`_distancia`.
        return;
      }

      // `setFullRoute` + `publishRemainingRoute(force: true)` resuelve solo
      // el progreso correcto sobre la ruta nueva (nearest-point completo,
      // sin ventana) — no hace falta preservar `_routeProgressIndex` a mano
      // como antes.
      _movementEngine.setFullRoute(_mathService.densifyPolyline(puntos));
      final currentMarker = _movementEngine.currentPosition ?? conductorLatLng;
      if (currentMarker != null) {
        _movementEngine.publishRemainingRoute(currentMarker, force: true);
      }

      final segundos = await vm.calcularTiempoEstimado();
      if (segundos != null) {
        final minutos = (segundos / 60).ceil();
        vm.setTiempoEstimado('$minutos min');
      }

      // Ajustar cámara solo en la primera carga (no en cada refresco). Como
      // `_actualizarRuta` solo se llama una vez desde `initState`, la guarda
      // de `_hasInitialCameraApplied` ya basta (antes se combinaba con
      // `isFirstLoad`, derivado de `_fullRoutePoints`, que dejó de existir).
      if (!_hasInitialCameraApplied) {
        _hasInitialCameraApplied = true;
        await _fitConductorDestinoCamera(
          _conductorLatLng ?? conductorLatLng,
          destinoLatLng,
        );
      }
    } finally {
      _isUpdatingRoute = false;
    }
  }

  /// Encola cada ubicación cruda del conductor en el motor compartido
  /// (interpolación + snap-to-route + heading) y dispara re-cálculo de ruta
  /// si se desvía >50m (cooldown 15s) — la parte de "cuándo re-rutear" es
  /// propia de esta pantalla (la del cliente en `TripTrackingViewModel` usa
  /// 40m/8s), el resto queda delegado en `_movementEngine`.
  void _enqueueConductorTarget(LatLng target) {
    final desvio = _movementEngine.distanceToRoute(target);
    final now = DateTime.now();
    final cooldownOk =
        _lastRouteCalcAt == null ||
        now.difference(_lastRouteCalcAt!).inSeconds >= 15;
    if (desvio != null && desvio > 50 && cooldownOk) {
      _lastRouteCalcAt = now;
      unawaited(_refreshRouteOnly());
    }

    _movementEngine.enqueueTarget(target);
    _movementEngine.refreshHeading();
    if (!mounted) return;
    setState(() {
      _conductorLatLng = _movementEngine.currentPosition;
      _conductorRotation = _movementEngine.headingNotifier.value;
    });
  }

  /// Recalcula la ruta sin resetear el progreso ni mover la cámara.
  Future<void> _refreshRouteOnly() async {
    if (_isUpdatingRoute || !mounted) return;
    _isUpdatingRoute = true;
    try {
      final vm = Provider.of<Rutaclientedestinoviewmodel>(
        context,
        listen: false,
      );
      final puntos = await vm.obtenerPolylineConductorDestino();
      if (puntos.isEmpty || !mounted) return;
      _movementEngine.setFullRoute(_mathService.densifyPolyline(puntos));
    } finally {
      _isUpdatingRoute = false;
    }
  }

  double _polylineDistance(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      total += _calculateDistance(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }
    return total;
  }

  String _distanceToLabel(double meters) =>
      MapHelper.formatDistanceMeters(meters);

  Future<void> _fitConductorDestinoCamera(
    LatLng? conductor,
    LatLng? destino,
  ) async {
    if (!mounted) return;
    final controller = _mapController;
    if (controller == null || conductor == null || destino == null) return;

    // Mismo patrón que RutaDestinoView._fitMarkers (pantalla del conductor):
    // un solo newLatLngBounds con padding fijo. El SDK de Google Maps ya
    // calcula el zoom que hace falta para que ambos puntos queden visibles,
    // sin necesitar zoom manual por distancia ni bounds "expandidos" a mano.
    final bounds = LatLngBounds(
      southwest: LatLng(
        Math.min(conductor.latitude, destino.latitude),
        Math.min(conductor.longitude, destino.longitude),
      ),
      northeast: LatLng(
        Math.max(conductor.latitude, destino.latitude),
        Math.max(conductor.longitude, destino.longitude),
      ),
    );

    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'RutaClienteDestinoView');
    }
  }

  // Detecta si el dispositivo tiene barra de navegación inferior (Android/iOS)
  bool hasNavigationBar(BuildContext context) {
    return MediaQuery.of(context).padding.bottom > 0;
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) => MapHelper.distanceMeters(LatLng(lat1, lon1), LatLng(lat2, lon2));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _movementEngine.remainingRoutePointsNotifier.removeListener(
      _onRemainingRouteChanged,
    );
    _movementEngine.dispose();
    _conductorLocationSub?.cancel();
    _conductorLocationFirestoreSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
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
    return PopScope(
      canPop: false,
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
    final conductorLatLng =
        _conductorLatLng ??
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        builder: (context) => _CompartirUbicacionSheet(url: url),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible aún')),
      );
    }
  }

  void _onHelpPressed(Rutaclientedestinoviewmodel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (ctx) => _AyudaConductorSheet(
        fotoConductor: vm.fotoConductor,
        nombreConductor: vm.nombreConductor,
        onEstadoSolicitud: () {
          Navigator.of(context).pushNamed(
            AppRoutes.ayudaEstadoSolicitud,
            arguments: {'solicitudId': widget.idSolicitud},
          );
        },
        onProblemasConductor: () {
          Navigator.of(context).pushNamed(
            AppRoutes.ayudaProblemasConductor,
            arguments: {
              'solicitudId': widget.idSolicitud,
              'nombreConductor': vm.nombreConductor,
            },
          );
        },
      ),
    );
  }

  void _onDetails(Rutaclientedestinoviewmodel vm) {
    final nombre = vm.nombreConductor.isNotEmpty
        ? vm.nombreConductor
        : 'Conductor';
    final destino = vm.direccionDestino.isNotEmpty ? vm.direccionDestino : '—';
    final valor = _formatPesos(vm.valorServicio);
    final pago = _metodoPagoLabel(vm.metodoPago);
    final pagoIcon = _metodoPagoIcon(vm.metodoPago);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (ctx) => _DetalleServicioSheet(
        nombreConductor: nombre,
        fotoConductor: vm.fotoConductor,
        fotoVehiculo: vm.fotoVehiculo,
        placaVehiculo: vm.placaVehiculo,
        destino: destino,
        valor: valor,
        pago: pago,
        pagoIcon: pagoIcon,
        esNequi: vm.metodoPago.toLowerCase().contains('nequi'),
      ),
    );
  }

  // Main content extracted for clarity
  Widget _buildMainContent(
    BuildContext context,
    Rutaclientedestinoviewmodel vm,
  ) {
    LatLng? destinoLatLng = (vm.latDestino != null && vm.lngDestino != null)
        ? LatLng(vm.latDestino!, vm.lngDestino!)
        : null;
    LatLng? conductorLatLng =
        _conductorLatLng ??
        ((vm.latConductor != null && vm.lngConductor != null)
            ? LatLng(vm.latConductor!, vm.lngConductor!)
            : null);
    final markers = <Marker>{
      if (destinoLatLng != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destinoLatLng,
          infoWindow: const InfoWindow(title: 'Destino'),
          icon:
              _destinoMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom > 0 ? mq.padding.bottom : 20.0.h;

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

        // Controles Inferiores — a la izquierda: FAB centrar + botón emergencia.
        Positioned(
          left: 16.w,
          bottom: safeBottom + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FloatingActionButton(
                heroTag: 'fab_centrar_cliente',
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
                    // Alejar: vista del destino con más contexto alrededor.
                    await _mapController!.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: destinoLatLng,
                          zoom: 17,
                          tilt: 0,
                        ),
                      ),
                    );
                    return;
                  }
                  // Acercar: perspectiva anclada en la ubicación actual del
                  // cliente, rotada hacia el destino (igual patrón que
                  // RutaDestinoView / getCameraPerspective), en vez de solo
                  // centrar norte-arriba en el punto azul nativo.
                  final persp = vm.getCameraPerspective();
                  if (persp != null) {
                    await _mapController!.animateCamera(
                      CameraUpdate.newCameraPosition(persp),
                    );
                    return;
                  }
                  // Sin datos suficientes para la perspectiva (fallback):
                  // centrar en la última ubicación conocida del cliente.
                  try {
                    Position? pos = await Geolocator.getLastKnownPosition();
                    pos ??= await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.high,
                      ),
                    );
                    if (!mounted || _mapController == null) return;
                    await _mapController!.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: LatLng(pos.latitude, pos.longitude),
                          zoom: 19,
                          tilt: 0,
                        ),
                      ),
                    );
                  } catch (e, st) {
                    ErrorReporter.report(
                      e,
                      st,
                      reason: 'RutaClienteDestinoView',
                    );
                  }
                },
              ),
              SizedBox(height: 10.h),
              const PanicButtonFab(),
            ],
          ),
        ),

        // Tarjeta Superior Flotante
        Positioned(
          top: 0.h,
          left: 0.w,
          right: 0.w,
          child: UserTripInfoCard(
            title: 'En camino al destino',
            isMoto: _isMoto,
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

        // Loader oculto para mantener continuidad visual del movimiento del taxi.
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
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          // Shift visual center down below the top info card
          padding: EdgeInsets.only(top: 180.h, bottom: 20.h),
          onMapCreated: (controller) {
            mapControllerSetter(controller);
          },
        ),
      ],
    );
  }
}

/// Contenido del bottom sheet de "Compartir ubicación" del conductor.
/// Extraído como widget propio para no cargar un builder inline grande en
/// `_shareLocation`.
class _CompartirUbicacionSheet extends StatelessWidget {
  final String url;

  const _CompartirUbicacionSheet({required this.url});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'Compartir ubicación',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 32.h),
            ElevatedButton.icon(
              icon: const Icon(Icons.map, color: Colors.white),
              label: const Text(
                'Google Maps',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              onPressed: () async {
                await launchUrl(Uri.parse(url));
              },
            ),
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              icon: const Icon(Icons.chat, color: Colors.white),
              label: const Text(
                'WhatsApp',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
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
  }
}

/// Contenido del bottom sheet de ayuda del conductor. Extraído como widget
/// propio para no cargar un builder inline grande en `_onHelpPressed`.
class _AyudaConductorSheet extends StatelessWidget {
  final String fotoConductor;
  final String nombreConductor;
  final VoidCallback onEstadoSolicitud;
  final VoidCallback onProblemasConductor;

  const _AyudaConductorSheet({
    required this.fotoConductor,
    required this.nombreConductor,
    required this.onEstadoSolicitud,
    required this.onProblemasConductor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.0.w, vertical: 16.0.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColores.primary,
                  backgroundImage: fotoConductor.isNotEmpty
                      ? NetworkImage(fotoConductor)
                      : null,
                  child: fotoConductor.isEmpty
                      ? const Icon(Icons.person, size: 24, color: Colors.white)
                      : null,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    nombreConductor.isNotEmpty ? nombreConductor : 'Conductor',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      color: AppColores.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            Divider(height: 1.h, color: Colors.black12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '¿Cuál es el estado de mi solicitud?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.black54,
              ),
              onTap: () {
                Navigator.pop(context);
                onEstadoSolicitud();
              },
            ),
            Divider(height: 1.h, color: Colors.black12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Problemas con el conductor',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.black54,
              ),
              onTap: () {
                Navigator.pop(context);
                onProblemasConductor();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido del bottom sheet de "Detalles del servicio". Extraído como
/// widget propio para no cargar un builder inline grande en `_onDetails`.
class _DetalleServicioSheet extends StatelessWidget {
  final String nombreConductor;
  final String fotoConductor;
  final String fotoVehiculo;
  final String placaVehiculo;
  final String destino;
  final String valor;
  final String pago;
  final IconData pagoIcon;
  final bool esNequi;

  const _DetalleServicioSheet({
    required this.nombreConductor,
    required this.fotoConductor,
    required this.fotoVehiculo,
    required this.placaVehiculo,
    required this.destino,
    required this.valor,
    required this.pago,
    required this.pagoIcon,
    required this.esNequi,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
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
              // Conductor + vehículo asignado.
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColores.primary,
                    backgroundImage: fotoConductor.isNotEmpty
                        ? NetworkImage(fotoConductor)
                        : null,
                    child: fotoConductor.isEmpty
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
                          'Conductor',
                          style: TextStyle(
                            color: AppColores.textSecondary,
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          nombreConductor,
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
                  SizedBox(width: 10.w),
                  _DetalleVehiculoChip(foto: fotoVehiculo, placa: placaVehiculo),
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
                iconImage: esNequi ? 'assets/img/nequi.png' : null,
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

/// Chip de vehículo: foto + placa. Estilo alineado con `TripDetailsSheet`.
class _DetalleVehiculoChip extends StatelessWidget {
  const _DetalleVehiculoChip({required this.foto, required this.placa});
  final String foto;
  final String placa;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            width: 72.w,
            height: 54.h,
            color: AppColores.grey200,
            child: foto.isNotEmpty
                ? Image.network(foto, fit: BoxFit.cover)
                : const Icon(Icons.local_taxi, color: AppColores.grey400),
          ),
        ),
        if (placa.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: AppColores.textPrimary,
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Text(
              placa.toUpperCase(),
              style: TextStyle(
                color: AppColores.textWhite,
                fontWeight: FontWeight.w800,
                fontSize: 12.sp,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
