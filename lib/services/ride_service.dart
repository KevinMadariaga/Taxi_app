import 'package:cloud_firestore/cloud_firestore.dart';

class RideService {

  
  Future<void> actualizarEstadoSolicitud(String solicitudId, String estado) async {
    final normalized = estado
        .toLowerCase()
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    final now = DateTime.now();
    final fechaTexto =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final horaTexto =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final updateData = <String, dynamic>{'estado': estado};

    if (normalized.contains('completad') ||
        normalized.contains('completed') ||
        normalized.contains('finaliz')) {
      updateData.addAll({
        'completedAt': FieldValue.serverTimestamp(),
        'fecha de terminacion': FieldValue.serverTimestamp(),
      });
    }

    await FirebaseFirestore.instance
        .collection("solicitudes")
        .doc(solicitudId)
        .update(updateData);
  }

  /// Escucha en tiempo real el estado de la solicitud
  Stream<String?> escucharEstadoSolicitud(String solicitudId) {
    return FirebaseFirestore.instance
        .collection("solicitudes")
        .doc(solicitudId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['estado'] as String?);
  }

  // Métodos específicos para cada estado
  Future<void> cancelarSolicitud(String solicitudId) async {
    await actualizarEstadoSolicitud(solicitudId, "cancelado");
  }

  Future<void> marcarEnCamino(String solicitudId) async {
    await actualizarEstadoSolicitud(solicitudId, "en camino");
  }

  Future<void> marcarCompletado(String solicitudId) async {
    await actualizarEstadoSolicitud(solicitudId, "completado");
  }
}
