import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FavoritosService {
  FavoritosService._();
  static final FavoritosService instance = FavoritosService._();

  final _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _favoritosRef(String uid) =>
      _fs.collection('usuarios').doc(uid).collection('favoritos');

  Future<QuerySnapshot<Map<String, dynamic>>> getFavoritosPorTipo(
    String uid,
    String tipo, {
    int? limit,
  }) {
    var q = _favoritosRef(uid).where('tipo', isEqualTo: tipo);
    if (limit != null) q = q.limit(limit);
    return q.get();
  }

  Future<void> guardarFavorito({
    required String uid,
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  }) async {
    final payload = {
      'userId': uid,
      'nombre': nombre,
      'direccion': direccion,
      'ubicacion': GeoPoint(ubicacion.latitude, ubicacion.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'tipo': tipo,
    };
    await _favoritosRef(uid).add(payload);
    await _fs.collection('ubicaciones').add(payload);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getTodasUbicaciones() {
    return _fs.collection('ubicaciones').get();
  }
}
