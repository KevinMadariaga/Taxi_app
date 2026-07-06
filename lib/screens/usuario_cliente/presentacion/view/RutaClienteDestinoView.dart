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
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/user_trip_info_card.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/panic_button_fab.dart';
import 'package:taxi_app/routes/app_routes.dart';

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
  Timer? _animacionMarcadorTimer;
  StreamSubscription<LatLng?>? _conductorLocationSub;
  StreamSubscription? _conductorLocationFirestoreSub;

  // =====================
  // Map & Route State
  // =====================
  LatLng? _conductorLatLng;
  List<LatLng> _fullRoutePoints = const [];
  final List<LatLng> _pendingConductorTargets = <LatLng>[];
  List<LatLng> _activePathPoints = const [];
  int _activePathIndex = 0;
  int _routeProgressIndex = 0;
  double _movementSpeedMps = 8.0;
  LatLng? _lastRawConductor;
  DateTime? _lastRawConductorAt;
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
    debugPrint(
      '[RutaClienteDestinoView] Escuchando ubicación del conductor para solicitud: ${widget.idSolicitud}',
    );
    _viewModel!.escucharUbicacionConductor(widget.idSolicitud);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await SessionHelper.setActiveSolicitud(widget.idSolicitud);
      try {
        await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino');
      } catch (_) {}
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
        // devuelve vacio temporalmente.
        if (_fullRoutePoints.isNotEmpty && _conductorLatLng != null) {
          final visibleRoute = _buildRemainingRoutePoints(_conductorLatLng!);
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
        return;
      }

      final newDense = _densifyPolyline(puntos);
      final isFirstLoad = _fullRoutePoints.isEmpty;
      if (isFirstLoad) {
        _fullRoutePoints = newDense;
        _routeProgressIndex = _conductorLatLng != null
            ? _nearestIndexRaw(_conductorLatLng!, _fullRoutePoints)
            : 0;
      } else {
        // Preservar progreso al refrescar ruta — no resetear a 0
        final savedMarker = _conductorLatLng;
        _fullRoutePoints = newDense;
        if (savedMarker != null) {
          _routeProgressIndex = _nearestIndexRaw(savedMarker, newDense);
        }
      }

      final currentMarker = _conductorLatLng ?? conductorLatLng;
      final visibleRoute = currentMarker != null
          ? _buildRemainingRoutePoints(currentMarker)
          : _fullRoutePoints;

      final distanciaStr = _distanceToLabel(_polylineDistance(visibleRoute));

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
        _distancia = distanciaStr;
      });

      final segundos = await vm.calcularTiempoEstimado();
      if (segundos != null) {
        final minutos = (segundos / 60).ceil();
        vm.setTiempoEstimado('$minutos min');
      }

      // Ajustar cámara solo en la primera carga (no en cada refresco)
      if (isFirstLoad && !_hasInitialCameraApplied) {
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

  void _enqueueConductorTarget(LatLng target) {
    final now = DateTime.now();
    if (_lastRawConductor != null && _lastRawConductorAt != null) {
      final elapsedMs = now.difference(_lastRawConductorAt!).inMilliseconds;
      if (elapsedMs > 0) {
        final moved = _calculateDistance(
          _lastRawConductor!.latitude,
          _lastRawConductor!.longitude,
          target.latitude,
          target.longitude,
        );
        final speed = moved / (elapsedMs / 1000.0);
        _movementSpeedMps = speed.clamp(3.0, 18.0);
      }
    }
    _lastRawConductor = target;
    _lastRawConductorAt = now;

    if (_conductorLatLng == null) {
      final initialRotation = _computeConductorHeading(
        target,
        _conductorRotation,
      );
      setState(() {
        _conductorLatLng = target;
        _conductorRotation = initialRotation;
      });
      return;
    }

    final snappedTarget = _snapTargetToRouteForward(target);

    // Evita agregar duplicados casi iguales que solo meten ruido al movimiento.
    if (_pendingConductorTargets.isNotEmpty) {
      final lastQueued = _pendingConductorTargets.last;
      final delta = _calculateDistance(
        lastQueued.latitude,
        lastQueued.longitude,
        snappedTarget.latitude,
        snappedTarget.longitude,
      );
      if (delta < 1.2) {
        return;
      }
    }

    if (_pendingConductorTargets.isEmpty && _conductorLatLng != null) {
      final deltaFromCurrent = _calculateDistance(
        _conductorLatLng!.latitude,
        _conductorLatLng!.longitude,
        snappedTarget.latitude,
        snappedTarget.longitude,
      );
      if (deltaFromCurrent < 1.2) {
        return;
      }
    }

    // Encola cada ubicacion escuchada para reproducir el recorrido completo.
    _pendingConductorTargets.add(snappedTarget);

    // Refresca ruta si el conductor se desvía (con cooldown de 15s)
    if (_fullRoutePoints.isNotEmpty) {
      final desvio = _distanceToNearestRoutePoint(snappedTarget);
      final now = DateTime.now();
      final cooldownOk = _lastRouteCalcAt == null ||
          now.difference(_lastRouteCalcAt!).inSeconds >= 15;
      if (desvio > 50 && cooldownOk) {
        _lastRouteCalcAt = now;
        unawaited(_refreshRouteOnly());
      }
    }

    _ensureMovementTimer();
  }

  void _ensureMovementTimer() {
    if (_animacionMarcadorTimer != null) return;
    _animacionMarcadorTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tickMovement(),
    );
  }

  void _tickMovement() {
    final currentMarker = _conductorLatLng;
    if (currentMarker == null) {
      _stopMovement();
      return;
    }

    if (_activePathPoints.isEmpty) {
      if (_pendingConductorTargets.isEmpty) {
        _stopMovement();
        return;
      }
      _prepareActivePath(currentMarker, _pendingConductorTargets.first);
    }

    final effectiveSpeed = _effectiveSpeedForBacklog(currentMarker);
    final stepMeters = effectiveSpeed * 0.05;
    var remaining = stepMeters;
    var current = currentMarker;

    while (remaining > 0 && _activePathIndex < _activePathPoints.length) {
      final next = _activePathPoints[_activePathIndex];
      final segmentDistance = _calculateDistance(
        current.latitude,
        current.longitude,
        next.latitude,
        next.longitude,
      );

      if (segmentDistance <= 0.1) {
        current = next;
        _activePathIndex += 1;
        continue;
      }

      if (remaining >= segmentDistance) {
        current = next;
        remaining -= segmentDistance;
        _activePathIndex += 1;
      } else {
        final t = remaining / segmentDistance;
        current = LatLng(
          current.latitude + (next.latitude - current.latitude) * t,
          current.longitude + (next.longitude - current.longitude) * t,
        );
        remaining = 0;
      }
    }

    final visibleRoute = _buildRemainingRoutePoints(current);
    final distance = _polylineDistance(visibleRoute);
    LatLng? headingTarget;
    if (_activePathIndex < _activePathPoints.length) {
      final lookAheadIndex = (_activePathIndex + 2) < _activePathPoints.length
          ? (_activePathIndex + 2)
          : (_activePathPoints.length - 1);
      headingTarget = _activePathPoints[lookAheadIndex];
    } else if (visibleRoute.length >= 2) {
      headingTarget = visibleRoute[1];
    }

    var nextRotation = _conductorRotation;
    if (headingTarget != null) {
      final heading = _bearingBetween(current, headingTarget);
      nextRotation = _lerpAngle(_conductorRotation, heading, 0.55);
    } else {
      nextRotation = _computeConductorHeading(current, _conductorRotation);
    }

    setState(() {
      _conductorLatLng = current;
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
      _distancia = _distanceToLabel(distance);
      _conductorRotation = nextRotation;
    });

    // Camera follow: cada 8 ticks (~400ms) recentra el mapa en el conductor,
    // orientado en su dirección de avance por la calle — antes eran 40 ticks
    // (2s), tan espaciado que el marcador se notaba "caminar" lejos del
    // centro entre cada corrección en vez de verse siempre centrado.
    _cameraFollowTick++;
    if (_cameraFollowTick >= 8 && !_mostrarSoloDestino && _mapController != null) {
      _cameraFollowTick = 0;
      unawaited(
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: current,
              bearing: nextRotation,
              zoom: 16.5,
              tilt: 0,
            ),
          ),
        ),
      );
    }

    if (_activePathIndex >= _activePathPoints.length) {
      if (_pendingConductorTargets.isNotEmpty) {
        _pendingConductorTargets.removeAt(0);
      }
      _activePathPoints = const [];
      _activePathIndex = 0;
    }
  }

  double _effectiveSpeedForBacklog(LatLng currentMarker) {
    var speed = _movementSpeedMps;
    final backlog = _pendingConductorTargets.length;

    // Si ya hay 2+ updates pendientes, acelera para no quedar atras.
    if (backlog >= 2) {
      speed *= (1.0 + (backlog - 1) * 0.35).clamp(1.0, 2.8);
    }

    if (backlog > 0) {
      final next = _pendingConductorTargets.first;
      final lagDistance = _calculateDistance(
        currentMarker.latitude,
        currentMarker.longitude,
        next.latitude,
        next.longitude,
      );

      if (lagDistance > 70) {
        speed *= 1.5;
      } else if (lagDistance > 40) {
        speed *= 1.3;
      } else if (lagDistance > 20) {
        speed *= 1.15;
      }
    }

    return speed.clamp(3.0, 28.0);
  }

  void _prepareActivePath(LatLng from, LatLng to) {
    final source = _fullRoutePoints;
    if (source.length < 2) {
      _activePathPoints = <LatLng>[to];
      _activePathIndex = 0;
      return;
    }

    final startIdx = _nearestForwardIndex(from, source);
    var endIdx = _nearestForwardIndex(to, source);
    if (endIdx < startIdx) {
      endIdx = startIdx;
    }

    if (startIdx <= endIdx) {
      final segment = source.sublist(startIdx, endIdx + 1);
      _activePathPoints = <LatLng>[...segment, to];
    } else {
      final segment = source.sublist(endIdx, startIdx + 1).reversed;
      _activePathPoints = <LatLng>[...segment, to];
    }
    _activePathIndex = 0;
  }

  void _stopMovement() {
    _animacionMarcadorTimer?.cancel();
    _animacionMarcadorTimer = null;
  }

  double _computeConductorHeading(LatLng current, double currentRotation) {
    final source = _fullRoutePoints;
    if (source.length < 2) return currentRotation;

    final nearest = _nearestForwardIndex(current, source);
    final lookAhead = nearest + 4;

    LatLng? target;
    if (lookAhead < source.length) {
      target = source[lookAhead];
    } else if (nearest < source.length - 1) {
      target = source[nearest + 1];
    } else if (nearest > 0) {
      target = source[nearest];
    }

    if (target == null) return currentRotation;
    final heading = _bearingBetween(current, target);
    return _lerpAngle(currentRotation, heading, 0.5);
  }

  LatLng _snapTargetToRouteForward(LatLng target) {
    final source = _fullRoutePoints;
    if (source.length < 2 || _conductorLatLng == null) {
      return target;
    }

    final start = _routeProgressIndex;
    final end = Math.min(source.length - 1, start + 240);
    var nearest = start;
    var best = double.infinity;

    for (var i = start; i <= end; i++) {
      final p = source[i];
      final dist = _calculateDistance(
        target.latitude,
        target.longitude,
        p.latitude,
        p.longitude,
      );
      if (dist < best) {
        best = dist;
        nearest = i;
      }
    }

    // Si el GPS cae muy lejos de la ruta, dejamos el punto original para
    // permitir recuperación de ruta sin bloquear el marcador.
    if (best > 80) {
      return target;
    }

    if (nearest > _routeProgressIndex) {
      _routeProgressIndex = nearest;
    }
    return source[_routeProgressIndex];
  }

  List<LatLng> _buildRemainingRoutePoints(LatLng current) {
    final source = _fullRoutePoints;
    if (source.length < 2) {
      return source;
    }

    final nearest = _nearestForwardIndex(current, source);
    if (nearest >= source.length - 1) {
      return <LatLng>[current, source.last];
    }

    final tail = source.sublist(nearest + 1);
    return <LatLng>[current, ...tail];
  }

  int _nearestForwardIndex(LatLng current, List<LatLng> source) {
    if (source.isEmpty) return 0;

    var nearest = _routeProgressIndex.clamp(0, source.length - 1);
    var best = double.infinity;
    final start = _routeProgressIndex.clamp(0, source.length - 1);
    final end = Math.min(source.length - 1, start + 260);
    for (var i = start; i <= end; i++) {
      final p = source[i];
      final dist = _calculateDistance(
        current.latitude,
        current.longitude,
        p.latitude,
        p.longitude,
      );
      if (dist < best) {
        best = dist;
        nearest = i;
      }
    }

    if (nearest > _routeProgressIndex) {
      _routeProgressIndex = nearest;
    }
    if (_routeProgressIndex >= source.length) {
      _routeProgressIndex = source.length - 1;
    }
    return _routeProgressIndex;
  }

  int _nearestIndexRaw(LatLng current, List<LatLng> source) {
    if (source.isEmpty) return 0;

    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < source.length; i++) {
      final p = source[i];
      final dist = _calculateDistance(
        current.latitude,
        current.longitude,
        p.latitude,
        p.longitude,
      );
      if (dist < best) {
        best = dist;
        nearest = i;
      }
    }
    return nearest;
  }

  List<LatLng> _densifyPolyline(List<LatLng> points) {
    if (points.length < 2) return points;
    const stepMeters = 4.0;
    final dense = <LatLng>[points.first];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segment = _calculateDistance(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (segment <= stepMeters) {
        dense.add(b);
        continue;
      }

      final steps = (segment / stepMeters).floor();
      for (var s = 1; s <= steps; s++) {
        final t = s / (steps + 1);
        dense.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
      }
      dense.add(b);
    }

    return dense;
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
      final newDense = _densifyPolyline(puntos);
      final savedMarker = _conductorLatLng;
      _fullRoutePoints = newDense;
      if (savedMarker != null) {
        _routeProgressIndex = _nearestIndexRaw(savedMarker, newDense);
      } else {
        _routeProgressIndex = 0;
      }
    } finally {
      _isUpdatingRoute = false;
    }
  }

  double _distanceToNearestRoutePoint(LatLng p) {
    if (_fullRoutePoints.isEmpty) return 0;
    var min = double.infinity;
    for (final pt in _fullRoutePoints) {
      final d = _calculateDistance(
        p.latitude,
        p.longitude,
        pt.latitude,
        pt.longitude,
      );
      if (d < min) min = d;
    }
    return min.isFinite ? min : 0;
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

  String _distanceToLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

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
    } catch (_) {}
  }

  // Detecta si el dispositivo tiene barra de navegación inferior (Android/iOS)
  bool hasNavigationBar(BuildContext context) {
    return MediaQuery.of(context).padding.bottom > 0;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animacionMarcadorTimer?.cancel();
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
        builder: (context) {
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
        },
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
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24.0.w,
              vertical: 16.0.h,
            ),
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
                      backgroundImage: vm.fotoConductor.isNotEmpty
                          ? NetworkImage(vm.fotoConductor)
                          : null,
                      child: vm.fotoConductor.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 24,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        vm.nombreConductor.isNotEmpty
                            ? vm.nombreConductor
                            : 'Conductor',
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
                    Navigator.pop(ctx);
                    Navigator.of(context).pushNamed(
                      AppRoutes.ayudaEstadoSolicitud,
                      arguments: {'solicitudId': widget.idSolicitud},
                    );
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
                    Navigator.pop(ctx);
                    Navigator.of(context).pushNamed(
                      AppRoutes.ayudaProblemasConductor,
                      arguments: {
                        'solicitudId': widget.idSolicitud,
                        'nombreConductor': vm.nombreConductor,
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
                  // Conductor + vehículo asignado.
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColores.primary,
                        backgroundImage: vm.fotoConductor.isNotEmpty
                            ? NetworkImage(vm.fotoConductor)
                            : null,
                        child: vm.fotoConductor.isEmpty
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
                      SizedBox(width: 10.w),
                      _DetalleVehiculoChip(
                        foto: vm.fotoVehiculo,
                        placa: vm.placaVehiculo,
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
                ],
              ),
            ),
          ),
        );
      },
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
    final safeBottom = mq.padding.bottom > 0 ? mq.padding.bottom: 20.0.h;

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
                  } catch (_) {}
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
