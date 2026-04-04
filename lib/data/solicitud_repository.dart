import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/firebase_service.dart';

class SolicitudRepository {
  /// Devuelve un stream en tiempo real del estado de la solicitud
  Stream<String?> estadoSolicitudStream(String solicitudId) {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((doc) => doc.data()?['estado'] as String?);
  }

  /// Guarda la ubicación del conductor en la solicitud
  Future<void> guardarUbicacionConductor(
    String solicitudId,
    double lat,
    double lng,
  ) async {
    try {
      debugPrint(
        '[SolicitudRepository] guardarUbicacionConductor -> solicitud:$solicitudId lat:$lat lng:$lng',
      );
      final svc = TripTrackingFirebaseService();
      final ts = DateTime.now().millisecondsSinceEpoch;
      await svc.actualizarUbicacionConductorEnSolicitud(
        solicitudId: solicitudId,
        location: LatLng(lat, lng),
        timestampMs: ts,
        appendRouteHistory: true,
      );
    } catch (e) {
      debugPrint('Error al guardar ubicación del conductor (servicio): $e');
    }
  }

  Future<Map<String, dynamic>?> getCliente(String solicitudId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final cliente = data['cliente'];
      if (cliente is Map<String, dynamic>) {
        return cliente;
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener cliente: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getConductor(String solicitudId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final conductor = data['conductor'];
      if (conductor is Map<String, dynamic>) {
        return conductor;
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener conductor: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getConductorUbicacion(
    String solicitudId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final conductor = data['conductor'];
      if (conductor is Map<String, dynamic>) {
        final ubicacion = conductor['ubicacion'];
        if (ubicacion is Map<String, dynamic>) {
          return ubicacion;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener ubicación del conductor: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getClienteUbicacion(String solicitudId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final cliente = data['cliente'];
      if (cliente is Map<String, dynamic>) {
        final ubicacion = cliente['ubicacion'];
        if (ubicacion is Map<String, dynamic>) {
          return ubicacion;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener ubicación del cliente: $e');
      return null;
    }
  }

  /// Devuelve un stream en tiempo real de la ubicación del conductor
  Stream<Map<String, dynamic>?> conductorUbicacionStream(String solicitudId) {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((doc) {
          final ubicacion = doc.data()?['conductor']?['ubicacion'];
          if (ubicacion is Map<String, dynamic>) {
            return ubicacion;
          }
          return null;
        });
  }
}
