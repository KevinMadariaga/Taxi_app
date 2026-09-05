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

  /// Busca el viaje completado más reciente del cliente que todavía no
  /// tiene calificación — se usa para bloquear el home hasta que termine de
  /// calificar el servicio anterior. `calificacion` está AUSENTE del doc (no
  /// `null` explícito) mientras no se califique, así que se filtra del lado
  /// del cliente en vez de usar `where('calificacion', isEqualTo: null)`:
  /// esa query de Firestore solo matchea documentos que tengan el campo
  /// explícitamente en `null`, no los que nunca lo escribieron.
  ///
  /// Sin `orderBy` a propósito: combinarlo con los dos filtros de igualdad
  /// de abajo pediría un índice compuesto nuevo. Con `limit(20)` alcanza —
  /// un cliente no acumula tantos viajes completados sin calificar entre
  /// sesión y sesión.
  Future<String?> buscarViajeCompletadoSinCalificar(String clienteId) async {
    final snap = await _firestore
        .collection('solicitudes')
        .where('cliente.id', isEqualTo: clienteId)
        .where('estado', isEqualTo: 'completado')
        .limit(20)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? masReciente;
    Timestamp? masRecienteTs;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['calificacion'] != null) continue;
      final ts =
          data['fecha de terminacion'] as Timestamp? ??
          data['updatedAt'] as Timestamp?;
      final tsAnterior = masRecienteTs;
      final esMasReciente =
          masReciente == null ||
          (ts != null && (tsAnterior == null || ts.compareTo(tsAnterior) > 0));
      if (esMasReciente) {
        masReciente = doc;
        masRecienteTs = ts;
      }
    }
    return masReciente?.id;
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

    // El promedio agregado en `usuarios/{conductorId}` lo escribe la Cloud
    // Function `onCalificacionRegistrada` (functions/index.js), no el
    // cliente: `firestore.rules` solo permite `update` en `usuarios/{uid}`
    // al dueño del doc o a un admin, así que un intento de escritura directa
    // acá siempre fallaba con permission-denied (hallazgo QA en dispositivo
    // real, 2026-09-05) y el promedio nunca se actualizaba.
  }
}
