import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/trip_route_math_service.dart';

/// Motor de animación/smoothing de la posición del conductor sobre el mapa.
///
/// Extraído de `TripTrackingViewModel` (comunidad de menor cohesión del repo
/// según graphify-out/GRAPH_REPORT.md, 0.02) — antes este estado (timer de
/// 50ms, backlog de updates, saltos grandes, snap-to-route) vivía mezclado
/// con binding de Firestore, chat y formatters de presentación en la misma
/// clase de ~1000 líneas.
///
/// Solo depende de [TripRouteMathService] (matemática pura, sin red/IO) —
/// deliberadamente NO depende de `MapService` para mantenerlo desacoplado de
/// la capa de red/Cloud Functions.
class ConductorMovementSimulator {
  ConductorMovementSimulator({TripRouteMathService? mathService})
    : _mathService = mathService ?? const TripRouteMathService();

  final TripRouteMathService _mathService;

  final ValueNotifier<LatLng?> positionNotifier = ValueNotifier<LatLng?>(null);
  final ValueNotifier<double> headingNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<List<LatLng>> remainingRoutePointsNotifier =
      ValueNotifier<List<LatLng>>(const []);

  /// Se dispara en cada tick del motor de movimiento (cada 50ms mientras hay
  /// animación en curso), independientemente de si la ruta restante se
  /// recalculó en ese tick. El viewmodel lo usa para su propio notify
  /// "pesado" throttleado (Scaffold/Card), igual que antes.
  VoidCallback? onTick;

  /// Se dispara cuando ocurre un snap (salto grande o resume tras
  /// background): la ruta planeada puede ya no reflejar el camino real, el
  /// viewmodel debe forzar un recálculo contra el servicio de mapas y hacer
  /// su propio notify inmediato.
  VoidCallback? onSnap;

  List<LatLng> _fullRoutePoints = const [];
  int _routeProgressIndex = 0;

  LatLng? _smoothed;
  final List<LatLng> _pendingTargets = <LatLng>[];
  List<LatLng> _activePathPoints = const [];
  int _activePathIndex = 0;
  Timer? _timer;
  double _movementSpeedMps = 8.0;
  LatLng? _lastRawTarget;
  DateTime? _lastRawTargetAt;
  bool _paused = false;
  bool _disposed = false;

  DateTime? _lastRebuildAt;
  static const _rebuildInterval = Duration(milliseconds: 200);

  // Umbral a partir del cual un update se considera un "salto" (navegación
  // externa en background, pérdida de conectividad, app suspendida) en vez de
  // movimiento normal — y se aplica de una vez en vez de animarlo como un
  // crawl. Ver `_snapTo`: sin esto, un salto de cientos de metros a
  // velocidad de calle podía mantener el timer de 50ms corriendo por más de
  // un minuto seguido, saturando el hilo principal (ANR).
  static const _largeJumpDistanceMeters = 200.0;
  static const _largeGapDuration = Duration(seconds: 25);

  LatLng? get currentPosition => _smoothed;

  /// Reemplaza la ruta completa (densificada) usada como referencia para
  /// heading y snap-to-route. No dispara recálculo de ruta restante ni
  /// heading — para eso ver [publishRemainingRoute] y el recálculo
  /// automático dentro de cada tick.
  void setFullRoute(List<LatLng> denseRoutePoints) {
    _fullRoutePoints = denseRoutePoints;
    _routeProgressIndex = 0;
  }

  /// Restaura la posición mostrada sin pasar por la lógica de smoothing
  /// (usado al restaurar desde cache local, antes de la primera actualización
  /// real de Firestore). A diferencia de [enqueueTarget], no altera el
  /// bookkeeping de velocidad/último-target-crudo.
  void restorePosition(LatLng position) {
    _smoothed = position;
    positionNotifier.value = position;
  }

  /// Publica directamente puntos ya calculados como "ruta restante" (dump
  /// crudo, sin recomputar contra la posición actual) — usado al restaurar
  /// desde cache, donde la ruta cacheada se muestra tal cual venía guardada.
  void restoreRemainingRoute(List<LatLng> points) {
    remainingRoutePointsNotifier.value = points;
  }

  /// Recalcula la ruta restante desde [current] y la publica. `force: true`
  /// bypassea el throttle de 200ms (usado tras fetch de ruta nueva o snap);
  /// sin `force`, respeta el throttle (usado dentro de cada tick).
  void publishRemainingRoute(LatLng current, {bool force = false}) {
    _rebuildRemainingRoute(current, force: force);
  }

  /// Recalcula el heading sin esperar al próximo tick — se usa tras cada
  /// actualización de Firestore (llega cada pocos segundos, no cada 50ms),
  /// igual que el `_updateConductorHeading()` original.
  void refreshHeading() {
    _computeHeading();
  }

  /// Distancia mínima (m) de [point] a la polilínea completa conocida
  /// (vértice más cercano; suficiente porque la ruta está densificada).
  double? distanceToRoute(LatLng point) {
    final source = _fullRoutePoints.length >= 2
        ? _fullRoutePoints
        : remainingRoutePointsNotifier.value;
    if (source.length < 2) return null;
    final distance = _mathService.nearestVertexDistanceMeters(point, source);
    return distance.isFinite ? distance : null;
  }

  /// Encola un nuevo dato crudo de posición del conductor. La primera vez que
  /// se llama (sin posición previa) se aplica directamente sin animar. Saltos
  /// grandes (>200m o gap >25s) se aplican de una vez vía [_snapTo]. El resto
  /// se anima gradualmente vía el timer de 50ms.
  void enqueueTarget(LatLng target) {
    final now = DateTime.now();
    var isLargeJump = false;
    if (_lastRawTarget != null && _lastRawTargetAt != null) {
      final elapsedMs = now.difference(_lastRawTargetAt!).inMilliseconds;
      if (elapsedMs > 0) {
        final distance = _mathService.haversineMeters(_lastRawTarget!, target);
        final speed = distance / (elapsedMs / 1000.0);
        _movementSpeedMps = speed.clamp(3.0, 18.0);
        isLargeJump =
            distance > _largeJumpDistanceMeters ||
            now.difference(_lastRawTargetAt!) > _largeGapDuration;
      }
    }
    _lastRawTarget = target;
    _lastRawTargetAt = now;

    if (_smoothed == null) {
      _smoothed = target;
      positionNotifier.value = target;
      return;
    }

    if (isLargeJump) {
      _snapTo(target);
      return;
    }

    final snappedTarget = _snapTargetToRouteForward(target);

    if (_pendingTargets.isNotEmpty) {
      final lastQueued = _pendingTargets.last;
      final delta = _mathService.haversineMeters(lastQueued, snappedTarget);
      if (delta < 1.2) return;
    }

    if (_pendingTargets.isEmpty && _smoothed != null) {
      final deltaFromCurrent = _mathService.haversineMeters(
        _smoothed!,
        snappedTarget,
      );
      if (deltaFromCurrent < 1.2) return;
    }

    _pendingTargets.add(snappedTarget);
    _ensureTimer();
  }

  /// Detiene la animación mientras la app está en background. En Android los
  /// `Timer` siguen corriendo aunque la app no sea visible — sin esto, cada
  /// tick seguía mutando el marcador/polyline contra un `GoogleMap` nativo
  /// sin superficie visible (pantalla negra al volver).
  void pause() {
    _paused = true;
    _stopTimer();
  }

  /// Al volver de background: no reanuda el crawl viejo (pudo quedar
  /// desactualizado por minutos) — aplica de una vez [latestRaw] (misma
  /// lógica que un salto grande). Si no hay posición conocida del conductor
  /// todavía, solo desbloquea el timer para el próximo update.
  void resume(LatLng? latestRaw) {
    _paused = false;
    if (latestRaw != null) {
      _snapTo(latestRaw);
    }
  }

  void dispose() {
    _disposed = true;
    _stopTimer();
    positionNotifier.dispose();
    headingNotifier.dispose();
    remainingRoutePointsNotifier.dispose();
  }

  void _snapTo(LatLng target) {
    _stopTimer();
    _pendingTargets.clear();
    _activePathPoints = const [];
    _activePathIndex = 0;

    _smoothed = target;
    positionNotifier.value = target;
    _routeProgressIndex = 0;
    _rebuildRemainingRoute(target, force: true);
    _computeHeading();

    onSnap?.call();
  }

  void _ensureTimer() {
    if (_paused || _disposed) return;
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _prepareActivePath(LatLng from, LatLng to) {
    final source = _fullRoutePoints.length >= 2
        ? _fullRoutePoints
        : remainingRoutePointsNotifier.value;
    if (source.length < 2) {
      _activePathPoints = <LatLng>[to];
      _activePathIndex = 0;
      return;
    }

    final startIdx = _mathService.nearestPointIndex(from, source);
    final endIdx = _mathService.nearestPointIndex(to, source);

    if (startIdx <= endIdx) {
      final segment = source.sublist(startIdx, endIdx + 1);
      _activePathPoints = <LatLng>[...segment, to];
    } else {
      final segment = source.sublist(endIdx, startIdx + 1).reversed;
      _activePathPoints = <LatLng>[...segment, to];
    }

    _activePathIndex = 0;
  }

  void _tick() {
    if (_smoothed == null) {
      _stopTimer();
      return;
    }

    if (_activePathPoints.isEmpty) {
      if (_pendingTargets.isEmpty) {
        _stopTimer();
        return;
      }
      _prepareActivePath(_smoothed!, _pendingTargets.first);
    }

    var current = _smoothed!;
    final effectiveSpeed = _effectiveSpeedForBacklog(current);
    final stepMeters = effectiveSpeed * 0.05;
    var remaining = stepMeters;

    while (remaining > 0 && _activePathIndex < _activePathPoints.length) {
      final next = _activePathPoints[_activePathIndex];
      final segmentDistance = _mathService.haversineMeters(current, next);

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

    _smoothed = current;
    positionNotifier.value = current;

    // Throttleado a 200ms: recalcular sobre `_fullRoutePoints` densificada
    // (cientos/miles de puntos) en cada tick de 50ms saturaba el hilo
    // principal en crawls largos — el origen del ANR documentado.
    _rebuildRemainingRoute(current);
    _computeHeading();
    onTick?.call();

    if (_activePathIndex >= _activePathPoints.length) {
      if (_pendingTargets.isNotEmpty) {
        _pendingTargets.removeAt(0);
      }
      _activePathPoints = const [];
      _activePathIndex = 0;
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  double _effectiveSpeedForBacklog(LatLng current) {
    var speed = _movementSpeedMps;
    final backlog = _pendingTargets.length;

    if (backlog >= 2) {
      speed *= (1.0 + (backlog - 1) * 0.35).clamp(1.0, 2.8);
    }

    if (backlog > 0) {
      final lagDistance = _mathService.haversineMeters(
        current,
        _pendingTargets.first,
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

  LatLng _snapTargetToRouteForward(LatLng target) {
    if (_fullRoutePoints.length < 2 || _smoothed == null) {
      return target;
    }
    final result = _mathService.snapForwardToRoute(
      target,
      _fullRoutePoints,
      _routeProgressIndex,
    );
    _routeProgressIndex = result.progressIndex;
    return result.point;
  }

  List<LatLng> _buildRemainingRoutePoints(LatLng current) {
    final source = _fullRoutePoints;
    final result = _mathService.remainingRoutePoints(
      current,
      source,
      _routeProgressIndex,
    );
    _routeProgressIndex = result.progressIndex;
    return result.points;
  }

  int _nearestForwardIndex(LatLng current, List<LatLng> source) {
    final next = _mathService.nearestForwardIndex(
      current,
      source,
      _routeProgressIndex,
    );
    _routeProgressIndex = next;
    return next;
  }

  void _rebuildRemainingRoute(LatLng current, {bool force = false}) {
    if (!force) {
      final now = DateTime.now();
      if (_lastRebuildAt != null &&
          now.difference(_lastRebuildAt!) < _rebuildInterval) {
        return;
      }
      _lastRebuildAt = now;
    }
    remainingRoutePointsNotifier.value = _buildRemainingRoutePoints(current);
  }

  void _computeHeading() {
    try {
      final current = _smoothed;
      final headingPoints = _fullRoutePoints.length >= 2
          ? _fullRoutePoints
          : remainingRoutePointsNotifier.value;
      if (current == null || headingPoints.length < 2) {
        headingNotifier.value = 0.0;
        return;
      }

      final nearest = _nearestForwardIndex(current, headingPoints);
      LatLng? target;
      final lookAhead = nearest + 3;
      if (lookAhead < headingPoints.length) {
        target = headingPoints[lookAhead];
      } else if (nearest < headingPoints.length - 1) {
        target = headingPoints[nearest + 1];
      } else if (nearest > 0) {
        target = headingPoints[nearest];
      }
      if (target != null) {
        headingNotifier.value = _mathService.bearingBetween(current, target);
      }
    } catch (_) {
      headingNotifier.value = 0.0;
    }
  }
}
