import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/favoritos_service.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../../dominio/repositorios/ubicaciones_repository.dart';

/// Delega en [FavoritosService] (ya resuelve Firestore: escribe a la vez en
/// `usuarios/{uid}/favoritos` y en el espejo plano `ubicaciones`) — no se
/// reimplementa el acceso a Firestore, solo se traduce su resultado a
/// [UbicacionEntity].
class UbicacionesRepositoryImpl implements UbicacionesRepository {
  UbicacionesRepositoryImpl({
    FavoritosService? favoritosService,
    FirebaseAuth? auth,
  }) : _favoritos = favoritosService ?? FavoritosService.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FavoritosService _favoritos;
  final FirebaseAuth _auth;

  String get _uidActual {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('No hay usuario autenticado.');
    }
    return uid;
  }

  UbicacionEntity? _mapDoc(Map<String, dynamic> data) {
    final geopoint = data['ubicacion'] as GeoPoint?;
    final nombre = (data['nombre'] ?? '') as String;
    final direccion = (data['direccion'] ?? '') as String;
    return UbicacionEntity(
      nombre: nombre,
      direccion: direccion.isNotEmpty ? direccion : nombre,
      position: geopoint == null
          ? null
          : LatLng(geopoint.latitude, geopoint.longitude),
      tipo: data['tipo'] as String?,
    );
  }

  @override
  Future<void> guardarFavorito({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  }) {
    return _favoritos.guardarFavorito(
      uid: _uidActual,
      nombre: nombre,
      direccion: direccion,
      ubicacion: ubicacion,
      tipo: tipo,
    );
  }

  @override
  Future<List<UbicacionEntity>> favoritosPorTipo(
    String tipo, {
    int? limit,
  }) async {
    final snapshot = await _favoritos.getFavoritosPorTipo(
      _uidActual,
      tipo,
      limit: limit,
    );
    return snapshot.docs
        .map((doc) => _mapDoc(doc.data()))
        .whereType<UbicacionEntity>()
        .where((u) => u.position != null)
        .toList();
  }

  @override
  Future<List<UbicacionEntity>> todasLasGuardadas() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const [];
    // El filtro por `userId` va en la query (no en Dart): además de ser lo
    // único que las reglas de `ubicaciones` permiten leer, evita descargar la
    // colección global entera en cada pulsación del buscador.
    final snapshot = await _favoritos.getUbicacionesDeUsuario(uid);
    return snapshot.docs
        .map((doc) => _mapDoc(doc.data()))
        .whereType<UbicacionEntity>()
        .toList();
  }
}
