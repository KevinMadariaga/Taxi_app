import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FavoritosService {
  // `firestore` inyectable (default a la instancia real) para poder testear
  // contra `fake_cloud_firestore` sin tocar el singleton de producción —
  // mismo patrón de wiring opcional que usa el resto del código
  // (`UbicacionesRepositoryImpl`, `SeleccionDestinoViewModel`, etc.).
  FavoritosService({FirebaseFirestore? firestore})
    : _fs = firestore ?? FirebaseFirestore.instance;

  static final FavoritosService instance = FavoritosService();

  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _favoritosRef(String uid) =>
      _fs.collection('usuarios').doc(uid).collection('favoritos');

  /// Todos los favoritos del usuario, sin filtrar por `tipo` ni ordenar
  /// server-side: el filtro y el orden se hacen en el repositorio, en Dart.
  /// Un `where('tipo')` dejaría invisibles (e imborrables) los docs legacy
  /// sin ese campo, y un `orderBy('createdAt')` combinado con ese `where`
  /// exigiría un índice compuesto.
  Future<QuerySnapshot<Map<String, dynamic>>> getFavoritos(
    String uid, {
    int? limit,
  }) {
    var q = _favoritosRef(uid) as Query<Map<String, dynamic>>;
    if (limit != null) q = q.limit(limit);
    return q.get();
  }

  /// Guarda el favorito y devuelve el id del documento creado — lo usa el
  /// caller para insertarlo en memoria sin necesidad de re-consultar.
  Future<String> guardarFavorito({
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
    final doc = await _favoritosRef(uid).add(payload);
    return doc.id;
  }

  Future<void> eliminarFavorito({
    required String uid,
    required String favoritoId,
  }) {
    return _favoritosRef(uid).doc(favoritoId).delete();
  }
}
