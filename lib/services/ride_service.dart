import 'package:cloud_firestore/cloud_firestore.dart';

class RideService {

  
  Future<void> actualizarEstadoSolicitud(String solicitudId, String estado) async {
    await FirebaseFirestore.instance
        .collection("solicitudes")
        .doc(solicitudId)
        .update({
      "estado": estado
    });
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
