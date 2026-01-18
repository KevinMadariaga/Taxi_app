import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Datos mínimos para rehidratar pantallas de ruta en reinicios.
class RouteCacheData {
  final String solicitudId;
  final String role; // 'cliente' | 'conductor'

  // Cliente
  final String? clientName;
  final String? clientAddress;
  final double? clientLat;
  final double? clientLng;

  // Conductor
  final String? conductorId;
  final String? conductorName;
  final String? conductorPhone;
  final String? conductorPlate;
  final String? conductorVehiclePhotoUrl;
  final String? conductorPhotoUrl;
  final double? conductorRating;

  const RouteCacheData({
    required this.solicitudId,
    required this.role,
    this.clientName,
    this.clientAddress,
    this.clientLat,
    this.clientLng,
    this.conductorId,
    this.conductorName,
    this.conductorPhone,
    this.conductorPlate,
    this.conductorVehiclePhotoUrl,
    this.conductorPhotoUrl,
    this.conductorRating,
  });

  Map<String, dynamic> toMap() => {
        'solicitudId': solicitudId,
        'role': role,
        'clientName': clientName,
        'clientAddress': clientAddress,
        'clientLat': clientLat,
        'clientLng': clientLng,
        'conductorId': conductorId,
        'conductorName': conductorName,
        'conductorPhone': conductorPhone,
        'conductorPlate': conductorPlate,
        'conductorPhotoUrl': conductorPhotoUrl,
        'conductorVehiclePhotoUrl': conductorVehiclePhotoUrl,
        'conductorRating': conductorRating,
      };

  static RouteCacheData? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return RouteCacheData(
      solicitudId: (m['solicitudId'] ?? '') as String,
      role: (m['role'] ?? '') as String,
      clientName: m['clientName'] as String?,
      clientAddress: m['clientAddress'] as String?,
      clientLat: (m['clientLat'] as num?)?.toDouble(),
      clientLng: (m['clientLng'] as num?)?.toDouble(),
      conductorId: m['conductorId'] as String?,
      conductorName: m['conductorName'] as String?,
      conductorPhone: m['conductorPhone'] as String?,
      conductorPlate: m['conductorPlate'] as String?,
      conductorVehiclePhotoUrl: m['conductorVehiclePhotoUrl'] as String?,
      conductorPhotoUrl: m['conductorPhotoUrl'] as String?,
      conductorRating: (m['conductorRating'] as num?)?.toDouble(),
    );
  }
}

class RouteCacheService {
  static String _keyFor(String solicitudId) => 'route_cache_$solicitudId';
  static const String _activeKey = 'active_solicitud_id';

  static Future<void> saveForSolicitud(RouteCacheData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(data.solicitudId), jsonEncode(data.toMap()));
    await prefs.setString(_activeKey, data.solicitudId);
  }

  static Future<RouteCacheData?> loadForSolicitud(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(solicitudId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return RouteCacheData.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getActiveSolicitudId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<void> clearSolicitud(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(solicitudId));
    final active = prefs.getString(_activeKey);
    if (active == solicitudId) {
      await prefs.remove(_activeKey);
    }
  }
}
