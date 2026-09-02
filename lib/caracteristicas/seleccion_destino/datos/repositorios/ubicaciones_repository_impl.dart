import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/favoritos_service.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../../dominio/repositorios/ubicaciones_repository.dart';

/// Delega en [FavoritosService] (ya resuelve Firestore, `usuarios/{uid}/favoritos`
/// es la única fuente) — no se reimplementa el acceso a Firestore, solo se
/// traduce su resultado a [UbicacionEntity].
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

  UbicacionEntity _mapDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final geopoint = data['ubicacion'] as GeoPoint?;
    final nombre = (data['nombre'] ?? '') as String;
    final direccion = (data['direccion'] ?? '') as String;
    return UbicacionEntity(
      id: doc.id,
      nombre: nombre,
      direccion: direccion.isNotEmpty ? direccion : nombre,
      position: geopoint == null
          ? null
          : LatLng(geopoint.latitude, geopoint.longitude),
      tipo: data['tipo'] as String?,
    );
  }

  /// Orden por `createdAt` desc, hecho en Dart (no server-side, ver
  /// [FavoritosService.getFavoritos]). Un doc recién creado localmente llega
  /// con `createdAt == null` hasta que el servidor confirma el
  /// `serverTimestamp` — se lo trata como "el más reciente", no como el más
  /// viejo, para que no salte de posición apenas confirma.
  int _porFechaDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ta = a.data()['createdAt'] as Timestamp?;
    final tb = b.data()['createdAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  }

  @override
  Future<String> guardarFavorito({
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
  Future<void> eliminarFavorito(String id) {
    return _favoritos.eliminarFavorito(uid: _uidActual, favoritoId: id);
  }

  @override
  Future<List<UbicacionEntity>> favoritos({int? limit}) async {
    final snapshot = await _favoritos.getFavoritos(_uidActual, limit: limit);
    final docs = snapshot.docs.where((doc) {
      final tipo = doc.data()['tipo'] as String?;
      return tipo == null || tipo == 'Favorito';
    }).toList()
      ..sort(_porFechaDesc);
    return docs.map(_mapDoc).toList();
  }

  @override
  Future<List<UbicacionEntity>> todasLasGuardadas() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const [];
    final snapshot = await _favoritos.getFavoritos(uid);
    final docs = snapshot.docs.toList()..sort(_porFechaDesc);
    return docs.map(_mapDoc).toList();
  }
}
