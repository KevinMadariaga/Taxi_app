import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../../dominio/repositorios/historial_destinos_repository.dart';

/// Historial local (no Firestore): es una comodidad de UX, no un dato de
/// negocio que valga la pena sincronizar entre dispositivos ni cubrir con
/// reglas de seguridad — vive en `SharedPreferences`, con la key aislada por
/// uid (mismo criterio que `bienvenida_vista_$uid` en `InicioClienteView`)
/// para no mezclar historiales si dos cuentas comparten el dispositivo.
class HistorialDestinosRepositoryImpl implements HistorialDestinosRepository {
  HistorialDestinosRepositoryImpl({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const _maxEntradas = 6;

  Future<String> _key() async {
    final uid = _auth.currentUser?.uid ?? 'anon';
    return 'historial_destinos_$uid';
  }

  @override
  Future<List<UbicacionEntity>> obtener() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(await _key()) ?? const <String>[];
    return raw.map(_decode).whereType<UbicacionEntity>().toList();
  }

  @override
  Future<void> registrar(UbicacionEntity destino) async {
    if (destino.position == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = await _key();
    final actuales = (prefs.getStringList(key) ?? const <String>[])
        .map(_decode)
        .whereType<UbicacionEntity>()
        .toList();

    actuales.removeWhere((e) => _mismaUbicacion(e, destino));
    actuales.insert(0, destino);
    final recortado = actuales.length > _maxEntradas
        ? actuales.sublist(0, _maxEntradas)
        : actuales;

    await prefs.setStringList(key, recortado.map(_encode).toList());
  }

  bool _mismaUbicacion(UbicacionEntity a, UbicacionEntity b) {
    final posA = a.position;
    final posB = b.position;
    if (posA == null || posB == null) return false;
    const epsilon = 0.0001; // ~11 m
    return (posA.latitude - posB.latitude).abs() < epsilon &&
        (posA.longitude - posB.longitude).abs() < epsilon;
  }

  String _encode(UbicacionEntity u) {
    return jsonEncode({
      'nombre': u.nombre,
      'direccion': u.direccion,
      'lat': u.position!.latitude,
      'lng': u.position!.longitude,
    });
  }

  UbicacionEntity? _decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final lat = (map['lat'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return UbicacionEntity(
        nombre: (map['nombre'] as String?) ?? '',
        direccion: (map['direccion'] as String?) ?? '',
        position: LatLng(lat, lng),
        tipo: 'reciente',
      );
    } catch (_) {
      return null;
    }
  }
}
