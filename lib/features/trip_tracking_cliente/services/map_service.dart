import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapService {
  // La key de Google Directions vive solo en Secret Manager, del lado del
  // servidor (ver functions/index.js → getDirectionsRoute). Nunca se compila
  // en la app: antes estaba hardcodeada acá y era extraíble del APK/IPA con
  // reversing básico.
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  DateTime? _lastRouteRequestAt;
  List<LatLng>? _lastRoute;
  String? _lastRouteKey;

  double distanceMeters(LatLng from, LatLng to) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLng = _degToRad(to.longitude - from.longitude);
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double routeDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceMeters(points[i - 1], points[i]);
    }
    return total;
  }

  Duration etaFromDistance(
    double distanceMeters, {
    double averageSpeedKmh = 28,
  }) {
    final speedMetersPerSecond = (averageSpeedKmh * 1000) / 3600;
    if (speedMetersPerSecond <= 0) return Duration.zero;
    final seconds = (distanceMeters / speedMetersPerSecond).round();
    return Duration(seconds: seconds);
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
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  Future<List<LatLng>> fetchRoadPolyline({
    required LatLng from,
    required LatLng to,
  }) async {
    final key = _buildRouteKey(from, to);
    final now = DateTime.now();

    final canReuseRecent =
        _lastRouteKey == key &&
        _lastRoute != null &&
        _lastRoute!.isNotEmpty &&
        _lastRouteRequestAt != null &&
        now.difference(_lastRouteRequestAt!) < const Duration(seconds: 8);

    if (canReuseRecent) return _lastRoute!;

    // 1) Intentar Google Directions vía Cloud Function (la key nunca sale del
    // servidor, ver functions/index.js → getDirectionsRoute).
    try {
      final callable = _functions.httpsCallable('getDirectionsRoute');
      final result = await callable
          .call(<String, dynamic>{
            'originLat': from.latitude,
            'originLng': from.longitude,
            'destLat': to.latitude,
            'destLng': to.longitude,
          })
          .timeout(const Duration(seconds: 6));

      final encoded = (result.data as Map?)?['encodedPolyline'] as String?;
      if (encoded != null && encoded.isNotEmpty) {
        final points = _decodePolyline(encoded);
        if (points.isNotEmpty) {
          debugPrint(
            '[MapService] Google Directions (Cloud Function) fetched: ${points.length} points',
          );
          _lastRouteKey = key;
          _lastRoute = points;
          _lastRouteRequestAt = now;
          return points;
        }
      }
      debugPrint(
        '[MapService] Directions Cloud Function did not return usable route, falling back',
      );
    } catch (e) {
      debugPrint('[MapService] Directions Cloud Function call failed: $e');
    }

    // 2) Fallback: OSRM comunitario
    try {
      final uri = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return _straightLine(from, to);

      final jsonBody = json.decode(resp.body) as Map<String, dynamic>?;
      final routes = jsonBody?['routes'] as List<dynamic>?;
      final geometry = routes != null && routes.isNotEmpty
          ? routes.first['geometry'] as Map<String, dynamic>?
          : null;
      final coordinates = geometry?['coordinates'] as List<dynamic>?;

      if (coordinates == null || coordinates.isEmpty)
        return _straightLine(from, to);

      final points = coordinates
          .whereType<List<dynamic>>()
          .where((item) => item.length >= 2)
          .map(
            (item) => LatLng(
              (item[1] as num).toDouble(),
              (item[0] as num).toDouble(),
            ),
          )
          .toList();

      if (points.isEmpty) {
        debugPrint(
          '[MapService] OSRM returned empty geometry, falling back to straight line',
        );
        return _straightLine(from, to);
      }

      debugPrint('[MapService] OSRM route fetched: ${points.length} points');
      _lastRouteKey = key;
      _lastRoute = points;
      _lastRouteRequestAt = now;

      return points;
    } catch (_) {
      debugPrint(
        '[MapService] OSRM request failed, falling back to straight line',
      );
      return _straightLine(from, to);
    }
  }

  String _buildRouteKey(LatLng from, LatLng to) {
    String q(double value) => value.toStringAsFixed(4);
    return '${q(from.latitude)},${q(from.longitude)}|${q(to.latitude)},${q(to.longitude)}';
  }

  List<LatLng> _straightLine(LatLng from, LatLng to) {
    return [from, to];
  }

  // Decodificador de polilinea Google (encoded polyline algorithm)
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int shift = 0;
      int result = 0;
      while (true) {
        final int b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) break;
      }
      final int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      while (true) {
        final int b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) break;
      }
      final int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      final double latD = lat / 1e5;
      final double lngD = lng / 1e5;
      points.add(LatLng(latD, lngD));
    }
    return points;
  }

  double _degToRad(double value) => value * (math.pi / 180);
}
