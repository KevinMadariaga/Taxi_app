import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/solicitud_firestore_datasource.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Servicio centralizado para operaciones de Firebase relacionadas con:
/// - Ubicación (guardar y escuchar actualizaciones).
/// - Estado del viaje/solicitud.
class FirebaseService {
  FirebaseService({
    FirebaseFirestore? firestore,
    SolicitudFirestoreDatasource? solicitudDatasource,
  }) : _firestoreOverride = firestore,
       _solicitudDatasource =
           solicitudDatasource ??
           SolicitudFirestoreDatasource(firestore: firestore);

  final FirebaseFirestore? _firestoreOverride;
  final SolicitudFirestoreDatasource _solicitudDatasource;

  FirebaseFirestore get _firestore {
    if (_firestoreOverride != null) {
      return _firestoreOverride;
    }

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar FirebaseService.',
      );
    }

    return FirebaseFirestore.instance;
  }

  // ============================================================================
  // GUARDAR UBICACIÓN
  // ============================================================================

  /// Guarda o actualiza la ubicación de un cliente en Firestore.
  ///
  /// [clienteId] - ID del cliente.
  /// [position] - Coordenadas actuales (LatLng).
  /// [address] - Dirección legible (opcional).
  Future<void> guardarUbicacionCliente({
    required String clienteId,
    required LatLng position,
    String? address,
  }) async {
    try {
      final ubicacionPayload = <String, dynamic>{
        'ubicacion': {
          'lat': position.latitude,
          'lng': position.longitude,
          'lastUpdated': FieldValue.serverTimestamp(),
          if (address != null && address.trim().isNotEmpty)
            'address': address.trim(),
        },
      };

      await _firestore
          .collection('usuarios')
          .doc(clienteId)
          .set(ubicacionPayload, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Error al guardar ubicación del cliente: $e');
    }
  }

  /// Actualiza la ubicación del conductor dentro de una solicitud activa.
  ///
  /// [solicitudId] - ID de la solicitud.
  /// [position] - Coordenadas actuales del conductor.
  Future<void> actualizarUbicacionConductorEnSolicitud({
    required String solicitudId,
    required LatLng position,
  }) async {
    try {
      try {
        debugPrint(
          '[FirebaseService] actualizarUbicacionConductorEnSolicitud -> solicitud:$solicitudId lat:${position.latitude} lng:${position.longitude}',
        );
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'firebase_service');
      }
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'conductor.lat': position.latitude,
        'conductor.lng': position.longitude,
        'conductor.lastUpdated': FieldValue.serverTimestamp(),
        'conductor.ubicacion.lat': position.latitude,
        'conductor.ubicacion.lng': position.longitude,
        'conductor.ubicacion.lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception(
        'Error al actualizar ubicación del conductor en solicitud: $e',
      );
    }
  }

  // ============================================================================
  // ESCUCHAR UBICACIÓN
  // ============================================================================

  /// Escucha cambios en la ubicación de un conductor en tiempo real.
  ///
  /// Retorna un Stream que emite [LatLng] cada vez que cambia la ubicación.
  /// Si no se encuentra ubicación o hay error, emite `null`.
  Stream<LatLng?> escucharUbicacionConductor(String conductorId) {
    return _firestore.collection('usuarios').doc(conductorId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      final ubicacion = data['ubicacion'];
      if (ubicacion is! Map) return null;

      final lat = ubicacion['lat'] ?? ubicacion['latitude'];
      final lng =
          ubicacion['lng'] ?? ubicacion['longitude'] ?? ubicacion['longitud'];

      if (lat == null || lng == null) return null;

      return LatLng((lat as num).toDouble(), (lng as num).toDouble());
    });
  }

  /// Escucha cambios en la ubicación del conductor dentro de una solicitud.
  ///
  /// Retorna un Stream que emite [LatLng] cada vez que el conductor actualiza
  /// su posición en la solicitud activa.
  Stream<LatLng?> escucharUbicacionConductorEnSolicitud(String solicitudId) {
    return _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          final data = snapshot.data();
          if (data == null) return null;

          final conductor = data['conductor'];
          if (conductor is! Map) return null;

          final ubicacion = conductor['ubicacion'];
          if (ubicacion is! Map) return null;

          final lat = ubicacion['lat'] ?? ubicacion['latitude'];
          final lng = ubicacion['lng'] ?? ubicacion['longitude'];

          if (lat == null || lng == null) return null;

          return LatLng((lat as num).toDouble(), (lng as num).toDouble());
        });
  }

  // ============================================================================
  // ESTADO DEL VIAJE
  // ============================================================================

  /// Actualiza el estado de una solicitud/viaje.
  ///
  /// Estados comunes: 'buscando', 'asignado', 'en_progreso', 'completado', 'cancelado'.
  Future<void> actualizarEstadoViaje({
    required String solicitudId,
    required String nuevoEstado,
  }) async {
    try {
      await _solicitudDatasource.actualizarEstado(
        solicitudId: solicitudId,
        estado: nuevoEstado,
      );
    } catch (e) {
      throw Exception('Error al actualizar estado del viaje: $e');
    }
  }

  /// Escucha cambios en el estado de una solicitud/viaje en tiempo real.
  ///
  /// Retorna un Stream que emite el estado actual como [String].
  /// Si no existe el documento o el estado, emite `null`.
  Stream<String?> escucharEstadoViaje(String solicitudId) {
    return _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          final data = snapshot.data();
          if (data == null) return null;

          final status = data['status'] ?? data['estado'];
          return status?.toString();
        });
  }

  /// Marca el inicio de un viaje (cuando el conductor llega al origen).
  ///
  /// Actualiza el estado a [SolicitudEstado.enRuta] y registra la hora de inicio.
  Future<void> iniciarViaje(String solicitudId) async {
    try {
      await _solicitudDatasource.actualizarEstado(
        solicitudId: solicitudId,
        estado: SolicitudEstado.enRuta,
        extra: {'startedAt': FieldValue.serverTimestamp()},
      );
    } catch (e) {
      throw Exception('Error al iniciar el viaje: $e');
    }
  }

  /// Finaliza un viaje exitosamente.
  ///
  /// Actualiza el estado a 'completado' y registra la hora de finalización.
  Future<void> finalizarViaje(String solicitudId) async {
    try {
      await _solicitudDatasource.actualizarEstado(
        solicitudId: solicitudId,
        estado: SolicitudEstado.completado,
      );
    } catch (e) {
      throw Exception('Error al finalizar el viaje: $e');
    }
  }

  /// Cancela una solicitud/viaje.
  ///
  /// [razon] - Motivo de la cancelación (opcional).
  /// [canceladoPor] - Quién canceló: 'cliente', 'conductor', 'sistema' (opcional).
  Future<void> cancelarViaje({
    required String solicitudId,
    String? razon,
    String? canceladoPor,
  }) async {
    try {
      await _solicitudDatasource.marcarCancelada(
        solicitudId: solicitudId,
        canceladoPor: canceladoPor,
        razon: razon,
      );
    } catch (e) {
      throw Exception('Error al cancelar el viaje: $e');
    }
  }

  /// Obtiene el estado completo de una solicitud como snapshot único.
  ///
  /// Útil para obtener información detallada sin suscripciones en tiempo real.
  Future<Map<String, dynamic>?> obtenerEstadoSolicitud(
    String solicitudId,
  ) async {
    try {
      final doc = await _firestore
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      throw Exception('Error al obtener estado de la solicitud: $e');
    }
  }

  /// Escucha el documento completo de una solicitud en tiempo real.
  ///
  /// A diferencia de [escucharEstadoViaje] (que solo emite el estado como
  /// String), este expone el snapshot entero para consumidores que necesitan
  /// reaccionar a más de un campo (ej. detectar cuándo pasa a completado).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSolicitud(
    String solicitudId,
  ) {
    return _solicitudDatasource.watch(solicitudId);
  }
}
