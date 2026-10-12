import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/entidades/sancion_conductor.dart';
import '../../dominio/repositorios/sancion_conductor_repository.dart';

class SancionConductorRepositoryImpl implements SancionConductorRepository {
  SancionConductorRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      (_firestore ?? FirebaseFirestore.instance)
          .collection('sanciones_conductores')
          .doc(uid);

  @override
  Stream<SancionConductor> watch(String conductorId) =>
      _ref(conductorId).snapshots().map((s) => fromMap(s.data()));

  @override
  Future<SancionConductor> obtener(String conductorId) async =>
      fromMap((await _ref(conductorId).get()).data());

  /// `cancelaciones` llega como ms (lo escribe `functions/sanciones.js`).
  static SancionConductor fromMap(Map<String, dynamic>? data) {
    if (data == null) return SancionConductor.ninguna;
    final hasta = data['bloqueadoHasta'];
    final lista = data['cancelaciones'];
    return SancionConductor(
      bloqueadoHasta: hasta is Timestamp ? hasta.toDate() : null,
      cancelaciones: lista is List
          ? [
              for (final t in lista)
                if (t is num) DateTime.fromMillisecondsSinceEpoch(t.toInt()),
            ]
          : const [],
    );
  }
}
