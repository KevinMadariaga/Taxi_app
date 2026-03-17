import 'dart:convert';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class DriverRouteService {
  // Cost note:
  // - OSRM public API is free and avoids paid route APIs.
  // - If OSRM is unavailable, fallback to straight-line polyline and local math ETA.
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  DateTime? _lastRequestAt;
  String? _lastKey;
  List<LatLng>? _lastRoute;

  double distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  Duration etaFromDistance(double meters, {double avgSpeedKmh = 26}) {
    final speedMps = (avgSpeedKmh * 1000) / 3600;
    if (speedMps <= 0) return Duration.zero;
    return Duration(seconds: (meters / speedMps).round());
  }

  double polylineDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceMeters(points[i - 1], points[i]);
    }
    return total;
  }

  String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String formatEta(Duration eta) {
    if (eta.inMinutes <= 0) return '1 min';
    return '${eta.inMinutes} min';
  }

  LatLng midpoint(LatLng a, LatLng b) {
    return LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);
  }

  Future<List<LatLng>> fetchRoutePolyline({
    required LatLng from,
    required LatLng to,
  }) async {
    final now = DateTime.now();
    final key = _routeKey(from, to);

    final canReuse =
        _lastKey == key &&
        _lastRoute != null &&
        _lastRoute!.isNotEmpty &&
        _lastRequestAt != null &&
        now.difference(_lastRequestAt!) < const Duration(seconds: 8);
    if (canReuse) return _lastRoute!;

    try {
      final uri = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [from, to];

      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>?;
      final routes = jsonBody?['routes'] as List<dynamic>?;
      final geometry = routes != null && routes.isNotEmpty
          ? routes.first['geometry'] as Map<String, dynamic>?
          : null;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;

      if (coordinates == null || coordinates.isEmpty) return [from, to];

      final points = coordinates
          .whereType<List<dynamic>>()
          .where((item) => item.length >= 2)
          .map((item) => LatLng((item[1] as num).toDouble(), (item[0] as num).toDouble()))
          .toList(growable: false);

      if (points.isEmpty) return [from, to];

      _lastKey = key;
      _lastRoute = points;
      _lastRequestAt = now;
      return points;
    } catch (_) {
      return [from, to];
    }
  }

  String _routeKey(LatLng from, LatLng to) {
    String q(double value) => value.toStringAsFixed(4);
    return '${q(from.latitude)},${q(from.longitude)}|${q(to.latitude)},${q(to.longitude)}';
  }

  double _degToRad(double value) => value * (math.pi / 180.0);
}
