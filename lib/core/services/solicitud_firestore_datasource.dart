import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

class SolicitudFirestoreDatasource {
  SolicitudFirestoreDatasource({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore {
    if (_firestoreOverride != null) {
      return _firestoreOverride;
    }

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar SolicitudFirestoreDatasource.',
      );
    }

    return FirebaseFirestore.instance;
  }

  DocumentReference<Map<String, dynamic>> ref(String solicitudId) {
    return _firestore.collection('solicitudes').doc(solicitudId);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String solicitudId) {
    return ref(solicitudId).snapshots();
  }

  Future<void> actualizarEstado({
    required String solicitudId,
    required String estado,
    Map<String, dynamic>? extra,
  }) async {
    final normalized = SolicitudEstado.normalize(estado);
    final payload = <String, dynamic>{
      'estado': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (normalized == SolicitudEstado.completado) {
      payload.addAll({
        'completedAt': FieldValue.serverTimestamp(),
        'fecha de terminacion': FieldValue.serverTimestamp(),
      });
    }

    if (extra != null && extra.isNotEmpty) {
      payload.addAll(extra);
    }

    await ref(solicitudId).set(payload, SetOptions(merge: true));
  }

  Future<void> marcarCancelada({
    required String solicitudId,
    String? canceladoPor,
    String? razon,
    Map<String, dynamic>? extra,
  }) async {
    final payload = <String, dynamic>{
      'estado': SolicitudEstado.cancelado,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (canceladoPor != null && canceladoPor.isNotEmpty) {
      payload['cancelledBy'] = canceladoPor;
    }
    if (razon != null && razon.isNotEmpty) {
      payload['cancelReason'] = razon;
    }
    if (extra != null && extra.isNotEmpty) {
      payload.addAll(extra);
    }

    await ref(solicitudId).set(payload, SetOptions(merge: true));
  }

  Future<void> eliminarSolicitud({required String solicitudId}) async {
    await ref(solicitudId).delete();
  }
}
