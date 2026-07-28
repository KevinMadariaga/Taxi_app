import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/helpers/map_helper.dart';

class TripRouteMathService {
  const TripRouteMathService();

  // Nota: NO delega en `MapHelper.distanceMeters` (Geolocator) a propósito.
  // Este método corre en la ruta más caliente del proyecto: escaneos de
  // cientos de puntos en `nearestPointIndex`/snap-to-route, dentro del timer
  // de 50ms de `ConductorMovementSimulator`. Delegar en Geolocator rompió
  // (deterministicamente) el test de timing real
  // `trip_tracking_viewmodel_test.dart: pickupProgress avanza...` — el
  // overhead extra por llamada, multiplicado por cientos de invocaciones por
  // tick, hizo que el crawl avanzara menos distancia real de la esperada
  // dentro de la ventana de 6s del test. La fórmula sí es la misma
  // (Haversine); se mantiene inline por rendimiento, no por desconocimiento
  // de la duplicación.
  double haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  double polylineDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += haversineMeters(points[i - 1], points[i]);
    }
    return total;
  }

  int nearestPointIndex(LatLng current, List<LatLng> polyline) {
    if (polyline.isEmpty) return 0;
    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < polyline.length; i++) {
      final nextDistance = haversineMeters(current, polyline[i]);
      if (nextDistance < bestDistance) {
        bestDistance = nextDistance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double remainingDistanceMeters(LatLng current, List<LatLng> polyline) {
    if (polyline.length < 2) return 0;

    final idx = nearestPointIndex(current, polyline);
    var distance = haversineMeters(current, polyline[idx]);

    for (var i = idx + 1; i < polyline.length; i++) {
      distance += haversineMeters(polyline[i - 1], polyline[i]);
    }

    return distance;
  }

  Duration etaFromDistance(
    double distanceMeters, {
    double averageSpeedKmh = 26,
  }) {
    final speedMps = (averageSpeedKmh * 1000) / 3600;
    if (speedMps <= 0) return Duration.zero;
    final secs = (distanceMeters / speedMps).round();
    return Duration(seconds: secs <= 0 ? 60 : secs);
  }

  String formatDistance(double meters) => MapHelper.formatDistanceMeters(meters);

  String formatEta(Duration eta) {
    if (eta.inMinutes <= 0) return '1 min';
    return '${eta.inMinutes} min';
  }

  double minDistanceToPolylineMeters(LatLng point, List<LatLng> polyline) {
    if (polyline.length < 2) return double.infinity;

    var best = double.infinity;
    for (var i = 1; i < polyline.length; i++) {
      final next = _distancePointToSegmentMeters(
        point,
        polyline[i - 1],
        polyline[i],
      );
      if (next < best) best = next;
    }
    return best;
  }

  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final refLat = _degToRad(p.latitude);
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(refLat);

    final px = p.longitude * metersPerDegLng;
    final py = p.latitude * metersPerDegLat;
    final ax = a.longitude * metersPerDegLng;
    final ay = a.latitude * metersPerDegLat;
    final bx = b.longitude * metersPerDegLng;
    final by = b.latitude * metersPerDegLat;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final abSquared = (abx * abx) + (aby * aby);

    if (abSquared <= 0.000001) {
      final dx = px - ax;
      final dy = py - ay;
      return math.sqrt((dx * dx) + (dy * dy));
    }

    final projection = (apx * abx + apy * aby) / abSquared;
    final clamped = projection.clamp(0.0, 1.0);

    final closestX = ax + (abx * clamped);
    final closestY = ay + (aby * clamped);
    final dx = px - closestX;
    final dy = py - closestY;
    return math.sqrt((dx * dx) + (dy * dy));
  }

  /// Densifica `points` insertando puntos intermedios cada `stepMeters` (~6m
  /// por defecto): una ruta real de Directions/OSRM trae vértices espaciados
  /// de forma irregular (a veces cientos de metros), y snap-to-route/heading
  /// necesitan resolución fina y regular para no "cortar camino".
  List<LatLng> densifyPolyline(List<LatLng> points, {double stepMeters = 6.0}) {
    if (points.length < 2) return points;
    final dense = <LatLng>[points.first];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segment = haversineMeters(a, b);
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

  /// Índice más cercano a `current` en `source`, sin retroceder nunca por
  /// debajo de `progressIndex` (evita que la ruta restante "salte hacia
  /// atrás" por ruido de GPS). Quien llama debe guardar el índice devuelto y
  /// pasarlo de vuelta en la próxima llamada — esta clase no mantiene estado.
  int nearestForwardIndex(
    LatLng current,
    List<LatLng> source,
    int progressIndex,
  ) {
    if (source.isEmpty) return 0;
    final nearest = nearestPointIndex(current, source);
    var next = progressIndex;
    if (nearest > next) next = nearest;
    if (next >= source.length) next = source.length - 1;
    return next;
  }

  /// Puntos de ruta restantes desde `current` hacia adelante, junto con el
  /// nuevo `progressIndex` (monótono no-decreciente).
  ({List<LatLng> points, int progressIndex}) remainingRoutePoints(
    LatLng current,
    List<LatLng> source,
    int progressIndex,
  ) {
    if (source.length < 2) {
      return (points: source, progressIndex: progressIndex);
    }

    final nextProgress = nearestForwardIndex(current, source, progressIndex);
    final points = nextProgress >= source.length - 1
        ? <LatLng>[current, source.last]
        : <LatLng>[current, ...source.sublist(nextProgress + 1)];
    return (points: points, progressIndex: nextProgress);
  }

  /// Distancia (m) de `point` al vértice más cercano de `polyline` — no al
  /// segmento; suficiente porque la ruta ya viene densificada cada ~6m. Para
  /// una distancia punto-a-segmento exacta ver [minDistanceToPolylineMeters].
  double nearestVertexDistanceMeters(LatLng point, List<LatLng> polyline) {
    if (polyline.length < 2) return double.infinity;
    var min = double.infinity;
    for (final pt in polyline) {
      final d = haversineMeters(point, pt);
      if (d < min) min = d;
    }
    return min;
  }

  /// Ajusta `target` al punto de `source` más cercano dentro de una ventana
  /// hacia adelante desde `progressIndex` (evita que el marcador "corte
  /// camino" fuera de la polilínea real cuando el GPS crudo se desvía un
  /// poco). Si el punto más cercano en la ventana está a más de
  /// `maxSnapDistanceMeters`, devuelve `target` sin ajustar (asume que la
  /// polilínea ya no es representativa, p.ej. desvío real de ruta).
  ({LatLng point, int progressIndex}) snapForwardToRoute(
    LatLng target,
    List<LatLng> source,
    int progressIndex, {
    int lookaheadPoints = 240,
    double maxSnapDistanceMeters = 80,
  }) {
    if (source.length < 2) {
      return (point: target, progressIndex: progressIndex);
    }

    final start = progressIndex.clamp(0, source.length - 1);
    final end = (start + lookaheadPoints) < source.length
        ? (start + lookaheadPoints)
        : (source.length - 1);
    var nearest = start;
    var best = double.infinity;

    for (var i = start; i <= end; i++) {
      final dist = haversineMeters(target, source[i]);
      if (dist < best) {
        best = dist;
        nearest = i;
      }
    }

    if (best > maxSnapDistanceMeters) {
      return (point: target, progressIndex: progressIndex);
    }

    final next = nearest > progressIndex ? nearest : progressIndex;
    return (point: source[next], progressIndex: next);
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Bearing in degrees from point [a] to [b]. 0 = north, 90 = east.
  double bearingBetween(LatLng a, LatLng b) => MapHelper.bearingDegrees(a, b);
}
