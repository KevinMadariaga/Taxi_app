import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/solicitud_model.dart';

class FirebaseService {
  // Nota de costos:
  // - Firestore tiene free tier, pero cada lectura/escritura cuenta.
  // - Se usa 1 stream por solicitud y updates puntuales para evitar lecturas/escrituras innecesarias.
  FirebaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _solicitudRef(String solicitudId) {
    return _firestore.collection('solicitudes').doc(solicitudId);
  }

  Stream<SolicitudModel> watchSolicitud(String solicitudId) {
    return _solicitudRef(solicitudId).snapshots().map((doc) {
      if (!doc.exists) {
        throw StateError('La solicitud $solicitudId no existe');
      }
      return SolicitudModel.fromFirestore(doc);
    });
  }

  Stream<Map<String, dynamic>> watchSolicitudRaw(String solicitudId) {
    return _solicitudRef(solicitudId).snapshots().map((doc) {
      if (!doc.exists) {
        throw StateError('La solicitud $solicitudId no existe');
      }
      return doc.data() ?? <String, dynamic>{};
    });
  }

  Future<void> guardarRutaPersistida({
    required String solicitudId,
    required List<LatLng> points,
    required double distanceMeters,
    String source = 'google_directions',
    bool recalculatedByDeviation = false,
  }) async {
    final payload = points
        .map((point) => {'lat': point.latitude, 'lng': point.longitude})
        .toList(growable: false);

    await _solicitudRef(solicitudId).set({
      'tracking': {
        'route': {
          'points': payload,
          'distanceMeters': distanceMeters,
          'source': source,
          'recalculatedByDeviation': recalculatedByDeviation,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> actualizarUbicacionConductorEnSolicitud({
    required String solicitudId,
    required LatLng location,
    required int timestampMs,
    bool appendRouteHistory = true,
  }) async {
    final updateData = <String, dynamic>{
      'conductor.lat': location.latitude,
      'conductor.lng': location.longitude,
      'conductor.ubicacion.lat': location.latitude,
      'conductor.ubicacion.lng': location.longitude,
      'conductor.ubicacion.timestampMs': timestampMs,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (appendRouteHistory) {
      updateData['tracking.driverHistory'] = FieldValue.arrayUnion([
        {
          'lat': location.latitude,
          'lng': location.longitude,
          'timestampMs': timestampMs,
        },
      ]);
    }

    await _solicitudRef(solicitudId).set(updateData, SetOptions(merge: true));
  }

  Future<void> cancelarSolicitud({
    required String solicitudId,
    required String cancelledBy,
  }) async {
    final ref = _solicitudRef(solicitudId);

    await ref.set({
      'estado': 'cancelado',
      'cancelledBy': cancelledBy,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.delete();
  }

  Future<void> actualizarEstadoSolicitud({
    required String solicitudId,
    required String estado,
  }) async {
    final normalized = estado
        .toLowerCase()
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');


    final updateData = <String, dynamic>{
      'estado': estado,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (normalized.contains('completad') ||
        normalized.contains('completed') ||
        normalized.contains('finaliz')) {
      updateData.addAll({
        'completedAt': FieldValue.serverTimestamp(),
        'fecha de terminacion': FieldValue.serverTimestamp()
      });
    }

    await _solicitudRef(solicitudId).set(updateData, SetOptions(merge: true));
  }
}
