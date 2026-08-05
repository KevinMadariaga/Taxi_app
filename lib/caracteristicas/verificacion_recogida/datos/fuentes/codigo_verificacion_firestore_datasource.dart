import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';

/// Persiste el código de verificación como mapa anidado en el mismo
/// documento del viaje (`solicitudes/{id}.verificacion`), mismo estilo que
/// `tarifa.*`/`conductor.*` — no una colección nueva.
class CodigoVerificacionFirestoreDatasource {
  CodigoVerificacionFirestoreDatasource({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore {
    final override = _firestoreOverride;
    if (override != null) return override;

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar CodigoVerificacionFirestoreDatasource.',
      );
    }

    return FirebaseFirestore.instance;
  }

  DocumentReference<Map<String, dynamic>> _ref(String viajeId) {
    return _firestore.collection('solicitudes').doc(viajeId);
  }

  CodigoVerificacionEntity? _fromMap(Map<String, dynamic>? data) {
    final raw = data?['verificacion'];
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    final codigo = (map['codigo'] ?? '').toString();
    if (codigo.isEmpty) return null;

    final generadoEn = map['generadoEn'];
    final validadoEn = map['validadoEn'];

    return CodigoVerificacionEntity(
      codigo: codigo,
      generadoEn: generadoEn is Timestamp ? generadoEn.toDate() : null,
      validadoEn: validadoEn is Timestamp ? validadoEn.toDate() : null,
      intentosFallidos: (map['intentosFallidos'] as num?)?.toInt() ?? 0,
    );
  }

  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId) async {
    final snap = await _ref(viajeId).get();
    return _fromMap(snap.data());
  }

  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId) {
    return _ref(viajeId).snapshots().map((snap) => _fromMap(snap.data()));
  }

  Future<void> guardarCodigo(String viajeId, CodigoVerificacionEntity codigo) {
    return _ref(viajeId).set({
      'verificacion': {
        'codigo': codigo.codigo,
        'generadoEn': FieldValue.serverTimestamp(),
        'validadoEn': null,
        'intentosFallidos': 0,
      },
    }, SetOptions(merge: true));
  }

  Future<void> marcarValidado(String viajeId) {
    return _ref(viajeId).set({
      'verificacion': {'validadoEn': FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  }

  Future<void> incrementarIntentoFallido(String viajeId) {
    return _ref(viajeId).set({
      'verificacion': {'intentosFallidos': FieldValue.increment(1)},
    }, SetOptions(merge: true));
  }
}
