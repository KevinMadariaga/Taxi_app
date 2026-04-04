import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class TripRouteMathService {
  const TripRouteMathService();

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

  String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

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

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Bearing in degrees from point [a] to [b]. 0 = north, 90 = east.
  double bearingBetween(LatLng a, LatLng b) {
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);

    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final bearingRad = math.atan2(y, x);
    var bearingDeg = bearingRad * (180.0 / math.pi);
    bearingDeg = (bearingDeg + 360.0) % 360.0;
    return bearingDeg;
  }
}
