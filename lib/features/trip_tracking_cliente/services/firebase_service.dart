import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/services/solicitud_firestore_datasource.dart';

import '../models/solicitud_model.dart';

class TripTrackingFirebaseService {
  // Nota de costos:
  // - Firestore tiene free tier, pero cada lectura/escritura cuenta.
  // - Se usa 1 stream por solicitud y updates puntuales para evitar lecturas/escrituras innecesarias.
  TripTrackingFirebaseService({
    FirebaseFirestore? firestore,
    SolicitudFirestoreDatasource? solicitudDatasource,
  })  : _solicitudDatasource =
            solicitudDatasource ?? SolicitudFirestoreDatasource(firestore: firestore);

  final SolicitudFirestoreDatasource _solicitudDatasource;

  DocumentReference<Map<String, dynamic>> _solicitudRef(String solicitudId) {
    return _solicitudDatasource.ref(solicitudId);
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
    return _solicitudDatasource.watch(solicitudId).map((doc) {
      if (!doc.exists) {
        throw StateError('La solicitud $solicitudId no existe');
      }
      return doc.data() ?? <String, dynamic>{};
    });
  }

  /// Obtiene la data de la solicitud una sola vez (lectura puntual).
  Future<Map<String, dynamic>?> getSolicitudOnce(String solicitudId) async {
    try {
      final doc = await _solicitudDatasource.ref(solicitudId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      if (kDebugMode) debugPrint('[TripTrackingFirebaseService] getSolicitudOnce error: $e');
      return null;
    }
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

    try {
      // Log exact payload being persisted for runtime validation during testing.
      // This helps confirm writes happen roughly every meter as configured.
      // Remove or lower verbosity in production if needed.
      // ignore: avoid_print
      debugPrint('[TripTrackingFirebaseService] Persistiendo ubicación conductor -> solicitud:$solicitudId lat:${location.latitude} lng:${location.longitude} ts:$timestampMs appendHistory:$appendRouteHistory');
    } catch (_) {}

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
    await _solicitudDatasource.marcarCancelada(
      solicitudId: solicitudId,
      canceladoPor: cancelledBy,
    );
  }

  Future<void> actualizarEstadoSolicitud({
    required String solicitudId,
    required String estado,
  }) async {
    await _solicitudDatasource.actualizarEstado(
      solicitudId: solicitudId,
      estado: estado,
    );
  }
}
