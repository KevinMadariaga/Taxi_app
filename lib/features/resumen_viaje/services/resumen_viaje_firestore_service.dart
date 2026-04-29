import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/resumen_viaje_model.dart';

class ResumenViajeFirebaseService {
  ResumenViajeFirebaseService({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore {
    if (_firestoreOverride != null) {
      return _firestoreOverride;
    }

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar ResumenViajeFirebaseService.',
      );
    }

    return FirebaseFirestore.instance;
  }

  Stream<ResumenViajeModel> streamResumenViaje(String solicitudId) {
    return _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) {
            throw StateError('No se encontro la solicitud solicitada.');
          }

          final data = snap.data() ?? <String, dynamic>{};
          return ResumenViajeModel.fromFirestore(
            solicitudId: snap.id,
            data: data,
          );
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
