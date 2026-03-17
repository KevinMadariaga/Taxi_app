import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/resumen_viaje_model.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<ResumenViajeModel> streamResumenViaje(String solicitudId) {
    return _firestore.collection('solicitudes').doc(solicitudId).snapshots().map((snap) {
      if (!snap.exists) {
        throw StateError('No se encontro la solicitud solicitada.');
      }

      final data = snap.data() ?? <String, dynamic>{};
      return ResumenViajeModel.fromFirestore(solicitudId: snap.id, data: data);
    });
  }

  Future<void> guardarCalificacion({
    required String solicitudId,
    required double calificacion,
    required String comentarioCalificacion,
  }) async {
    await _firestore.collection('solicitudes').doc(solicitudId).update({
      'calificacion': calificacion,
      'comentarioCalificacion': comentarioCalificacion.trim(),
      'fechaCalificacion': FieldValue.serverTimestamp(),
    });
  }
}
