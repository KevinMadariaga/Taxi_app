import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Escribe reportes de usuario en la colección `reportes`. Antes
/// `ProblemasConductorView` escribía a Firestore directo desde el widget.
class ReportesService {
  ReportesService._();
  static final ReportesService instance = ReportesService._();

  Future<void> enviarReporteConductor({
    required String solicitudId,
    required String clienteId,
    required String conductor,
    required List<String> motivos,
    required String comentario,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('reportes').add({
        'tipo': 'problema_conductor',
        'solicitudId': solicitudId,
        'clienteId': clienteId,
        'conductor': conductor,
        'motivos': motivos,
        'comentario': comentario,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[ReportesService] Reporte de conductor enviado para $solicitudId');
    } catch (e) {
      debugPrint('[ReportesService] Error: $e');
      rethrow;
    }
  }

  /// Reporte que envía el CONDUCTOR sobre un problema con el cliente/viaje
  /// (antes `ReportarProblemaScreen` escribía a Firestore directo).
  Future<void> enviarReporteDeConductor({
    required String solicitudId,
    required String conductorId,
    required String tipo,
    required String descripcion,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('reportes').add({
        'solicitudId': solicitudId,
        'conductorId': conductorId,
        'rol': 'conductor',
        'tipo': tipo,
        'descripcion': descripcion,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[ReportesService] Reporte de conductor enviado para $solicitudId');
    } catch (e) {
      debugPrint('[ReportesService] Error: $e');
      rethrow;
    }
  }

  /// Cantidad de reportes sin revisar (badge de `AdminHubScreen`).
  Stream<int> watchNoVistosCount() {
    return FirebaseFirestore.instance
        .collection('reportes')
        .where('visto', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Lista completa de reportes, más reciente primero (tab de admin).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchReportes() {
    return FirebaseFirestore.instance
        .collection('reportes')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> marcarVisto(String reporteId) {
    return FirebaseFirestore.instance
        .collection('reportes')
        .doc(reporteId)
        .update({'visto': true});
  }
}
