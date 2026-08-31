import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

abstract class SolicitudRepository {
  /// Devuelve un stream en tiempo real del estado de la solicitud
  Stream<String?> estadoSolicitudStream(String solicitudId);

  Future<Map<String, dynamic>?> getCliente(String solicitudId);

  Future<Map<String, dynamic>?> getConductor(String solicitudId);

  Future<Map<String, dynamic>?> getConductorUbicacion(String solicitudId);

  Future<Map<String, dynamic>?> getClienteUbicacion(String solicitudId);

  /// Devuelve un stream en tiempo real de la ubicación del conductor
  Stream<Map<String, dynamic>?> conductorUbicacionStream(String solicitudId);

  /// Historial de solicitudes de un conductor (usado por
  /// `HistorialDetalleConductor`, antes armaba la query directo en el widget).
  Stream<QuerySnapshot<Map<String, dynamic>>> historialConductorStream(
    String conductorId,
  );
}

class SolicitudRepositoryImpl implements SolicitudRepository {
  /// Devuelve un stream en tiempo real del estado de la solicitud
  @override
  Stream<String?> estadoSolicitudStream(String solicitudId) {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((doc) => doc.data()?['estado'] as String?);
  }

  @override
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
    } catch (e, st) {
      debugPrint('Error al obtener cliente: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'SolicitudRepository.getCliente',
      );
      return null;
    }
  }

  @override
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
    } catch (e, st) {
      debugPrint('Error al obtener conductor: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'SolicitudRepository.getConductor',
      );
      return null;
    }
  }

  @override
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
    } catch (e, st) {
      debugPrint('Error al obtener ubicación del conductor: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'SolicitudRepository.getConductorUbicacion',
      );
      return null;
    }
  }

  @override
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
    } catch (e, st) {
      debugPrint('Error al obtener ubicación del cliente: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'SolicitudRepository.getClienteUbicacion',
      );
      return null;
    }
  }

  /// Devuelve un stream en tiempo real de la ubicación del conductor
  @override
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

  /// Historial de solicitudes de un conductor (usado por
  /// `HistorialDetalleConductor`, antes armaba la query directo en el widget).
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> historialConductorStream(
    String conductorId,
  ) {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .where('conductor.id', isEqualTo: conductorId)
        .snapshots();
  }
}
