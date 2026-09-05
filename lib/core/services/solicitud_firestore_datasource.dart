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

    // Ancla de servidor única para el temporizador de espera: sin esto,
    // cliente y conductor calculaban el remanente contra el momento en que
    // CADA dispositivo veía `en espera` por primera vez, así que el cliente
    // que entraba tarde a la pantalla volvía a ver 3:00 completos.
    // `ReportarLlegadaUseCase` es el único punto que escribe este estado,
    // así que el ancla no se mueve entre escrituras posteriores.
    if (normalized == SolicitudEstado.enEspera) {
      payload['esperaIniciadaEn'] = FieldValue.serverTimestamp();
    }

    if (extra != null && extra.isNotEmpty) {
      payload.addAll(extra);
    }

    final documento = ref(solicitudId);

    // 'sin respuesta' es la única transición de esta ruta que compite de
    // verdad con otro escritor: la dispara un `Timer.periodic` LOCAL del
    // conductor (`ViajeConductorViewModel._handleWaitingTimeoutNoResponse`)
    // contra el último snapshot que le llegó, no contra el servidor. Si el
    // cliente confirma "voy en camino" (`ConfirmarVoyEnCaminoUseCase`, MISMO
    // método) justo cuando el timer local del conductor ya iba a disparar,
    // ganaba quien escribiera último — el viaje podía quedar marcado 'sin
    // respuesta' pese a que el cliente sí había respondido (auditoría de
    // bugs). Se relee el estado FRESCO del servidor dentro de una
    // transacción y solo se escribe si todavía sigue en 'en espera'; si ya
    // no lo está, es un no-op silencioso (la carrera se perdió de forma
    // correcta, no es un error).
    if (normalized == SolicitudEstado.sinRespuesta) {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(documento);
        if (!snap.exists) return;
        final data = snap.data() ?? <String, dynamic>{};
        final estadoServidor = SolicitudEstado.normalize(
          (data['estado'] ?? data['status'] ?? '').toString(),
        );
        if (estadoServidor != SolicitudEstado.enEspera) return;
        tx.set(documento, payload, SetOptions(merge: true));
      });
      return;
    }

    await documento.set(payload, SetOptions(merge: true));
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

  /// Actualiza solo `conductor.*` (nombre/foto/placa/fotoVehiculo) sin tocar
  /// `estado` — a diferencia de `actualizarEstado`, que siempre lo escribe.
  /// Usado para propagar un cambio de perfil del conductor hecho a mitad de
  /// viaje. Las reglas de Firestore permiten esta escritura al conductor
  /// asignado (`isAssignedConductor()`), no solo al dueño de la solicitud.
  Future<void> actualizarInfoConductor({
    required String solicitudId,
    required Map<String, dynamic> datosConductor,
  }) async {
    if (datosConductor.isEmpty) return;
    final payload = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    for (final entry in datosConductor.entries) {
      payload['conductor.${entry.key}'] = entry.value;
    }
    await ref(solicitudId).update(payload);
  }
}
