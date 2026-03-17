import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mensaje_model.dart';
import '../models/solicitud_model.dart';

class CachedRouteData {
  const CachedRouteData({
    required this.points,
    required this.distanceMeters,
    required this.etaSeconds,
  });

  final List<LatLng> points;
  final double? distanceMeters;
  final int? etaSeconds;
}

class PendingConductorLocation {
  const PendingConductorLocation({
    required this.lat,
    required this.lng,
    required this.timestampMs,
  });

  final double lat;
  final double lng;
  final int timestampMs;

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'timestampMs': timestampMs,
    };
  }

  static PendingConductorLocation fromMap(Map<String, dynamic> map) {
    return PendingConductorLocation(
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalCacheService {
  // Gratis: SharedPreferences/local storage, sin costo de infraestructura.
  static const _solicitudPrefix = 'trip_cache_solicitud_';
  static const _routePrefix = 'trip_cache_route_';
  static const _messagesPrefix = 'trip_cache_messages_';
  static const _pendingConductorLocationsPrefix = 'trip_cache_pending_locations_';

  Future<void> saveSolicitud(SolicitudModel solicitud) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_solicitudPrefix${solicitud.id}';
    await prefs.setString(key, jsonEncode(solicitud.toCacheMap()));
  }

  Future<SolicitudModel?> readSolicitud(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_solicitudPrefix$solicitudId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SolicitudModel.fromCacheMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRoute({
    required String solicitudId,
    required List<LatLng> points,
    required double? distanceMeters,
    required int? etaSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_routePrefix$solicitudId';

    final payload = {
      'distanceMeters': distanceMeters,
      'etaSeconds': etaSeconds,
      'points': points
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(growable: false),
    };

    await prefs.setString(key, jsonEncode(payload));
  }

  Future<CachedRouteData?> readRoute(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_routePrefix$solicitudId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pointList = (map['points'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          )
          .toList(growable: false);

      return CachedRouteData(
        points: pointList,
        distanceMeters: (map['distanceMeters'] as num?)?.toDouble(),
        etaSeconds: (map['etaSeconds'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMessages({
    required String solicitudId,
    required List<MensajeModel> messages,
    int maxMessages = 80,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_messagesPrefix$solicitudId';
    final recent = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;

    await prefs.setString(
      key,
      jsonEncode(recent.map((m) => m.toMap()).toList(growable: false)),
    );
  }

  Future<List<MensajeModel>> readMessages(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_messagesPrefix$solicitudId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(MensajeModel.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearSolicitudData(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_solicitudPrefix$solicitudId');
    await prefs.remove('$_routePrefix$solicitudId');
    await prefs.remove('$_messagesPrefix$solicitudId');
    await prefs.remove('$_pendingConductorLocationsPrefix$solicitudId');
  }

  Future<void> appendPendingConductorLocation({
    required String solicitudId,
    required double lat,
    required double lng,
    int? timestampMs,
    int maxItems = 500,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pendingConductorLocationsPrefix$solicitudId';
    final current = await readPendingConductorLocations(solicitudId);

    final next = [
      ...current,
      PendingConductorLocation(
        lat: lat,
        lng: lng,
        timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final bounded = next.length > maxItems
        ? next.sublist(next.length - maxItems)
        : next;

    await prefs.setString(
      key,
      jsonEncode(bounded.map((item) => item.toMap()).toList(growable: false)),
    );
  }

  Future<List<PendingConductorLocation>> readPendingConductorLocations(
    String solicitudId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_pendingConductorLocationsPrefix$solicitudId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PendingConductorLocation.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearPendingConductorLocations(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pendingConductorLocationsPrefix$solicitudId');
  }
}
