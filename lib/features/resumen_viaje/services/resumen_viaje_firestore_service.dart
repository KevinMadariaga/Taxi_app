import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

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
    String conductorId = '',
  }) async {
    await _firestore.collection('solicitudes').doc(solicitudId).update({
      'calificacion': calificacion,
      'comentarioCalificacion': comentarioCalificacion.trim(),
      'fechaCalificacion': FieldValue.serverTimestamp(),
    });

    // Acumular el promedio en el doc del conductor para que se muestre en
    // futuras ofertas (usuarios y/o conductores, según donde exista).
    if (conductorId.trim().isNotEmpty) {
      await _acumularCalificacionConductor(conductorId.trim(), calificacion);
    }
  }

  /// Acumula la calificación del conductor SOLO en la colección `usuarios`
  /// (no se crea colección `conductores`). Guarda el promedio en
  /// `calificacionConductor` (campo solicitado) y mantiene `calificacionPromedio`
  /// + `totalCalificaciones` para que la modal de ofertas muestre las estrellas.
  Future<void> _acumularCalificacionConductor(
    String conductorId,
    double nuevaCalificacion,
  ) async {
    final ref = _firestore.collection('usuarios').doc(conductorId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final d = snap.data() ?? <String, dynamic>{};
        final total =
            (d['totalCalificaciones'] ?? d['totalRatings'] ?? 0) as num;
        final prom =
            (d['calificacionConductor'] ??
                    d['calificacionPromedio'] ??
                    d['calificacion'] ??
                    d['rating'] ??
                    0)
                as num;
        final nuevoTotal = total.toInt() + 1;
        final nuevoProm =
            ((prom.toDouble() * total.toInt()) + nuevaCalificacion) /
            nuevoTotal;
        tx.set(ref, {
          'calificacionConductor': nuevoProm,
          'calificacionPromedio': nuevoProm,
          'totalCalificaciones': nuevoTotal,
        }, SetOptions(merge: true));
      });
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'ResumenViajeFirestoreService: fallo al acumular calificación del conductor $conductorId',
      );
    }
  }
}
