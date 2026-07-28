import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';

class DriverRouteService {
  // Cost note:
  // - Prefer Google Directions via MapService adapter for better street-level accuracy.
  // - Fallback to OSRM if Directions fails.
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  final MapService _mapServiceAdapter = const MapService();

  DateTime? _lastRequestAt;
  String? _lastKey;
  List<LatLng>? _lastRoute;

  double distanceMeters(LatLng a, LatLng b) => MapHelper.distanceMeters(a, b);

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

  String formatDistance(double meters) => MapHelper.formatDistanceMeters(meters);

  String formatEta(Duration eta) {
    if (eta.inMinutes <= 0) return '1 min';
    return '${eta.inMinutes} min';
  }

  LatLng midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
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
      // Intentar primero con el MapServiceAdapter (Google Directions + Fallback)
      final points = await _mapServiceAdapter.getRoutePolyline(from, to);
      if (points.isNotEmpty) {
        _lastKey = key;
        _lastRoute = points;
        _lastRequestAt = now;
        return points;
      }

      // Fallback manual a OSRM si el adapter no retorna puntos
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

      final pts = coordinates
          .whereType<List<dynamic>>()
          .where((item) => item.length >= 2)
          .map(
            (item) => LatLng(
              (item[1] as num).toDouble(),
              (item[0] as num).toDouble(),
            ),
          )
          .toList(growable: false);

      if (pts.isEmpty) return [from, to];

      _lastKey = key;
      _lastRoute = pts;
      _lastRequestAt = now;
      return pts;
    } catch (_) {
      return [from, to];
    }
  }

  String _routeKey(LatLng from, LatLng to) {
    String q(double value) => value.toStringAsFixed(4);
    return '${q(from.latitude)},${q(from.longitude)}|${q(to.latitude)},${q(to.longitude)}';
  }
}
