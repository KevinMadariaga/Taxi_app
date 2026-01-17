import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Servicio centralizado para operaciones de Firebase relacionadas con:
/// - Ubicación (guardar y escuchar actualizaciones).
/// - Estado del viaje/solicitud.
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================================================
  // GUARDAR UBICACIÓN
  // ============================================================================

  /// Guarda o actualiza la ubicación de un conductor en Firestore.
  ///
  /// [conductorId] - ID del conductor.
  /// [position] - Coordenadas actuales (LatLng).
  /// [address] - Dirección legible (opcional).
  Future<void> guardarUbicacionConductor({
    required String conductorId,
    required LatLng position,
    String? address,
  }) async {
    try {
      await _firestore.collection('conductor').doc(conductorId).update({
        'ubicacion': {
          'lat': position.latitude,
          'lng': position.longitude,
          'address': address ?? '',
          'lastUpdated': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      throw Exception('Error al guardar ubicación del conductor: $e');
    }
  }

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
      await _firestore.collection('cliente').doc(clienteId).update({
        'ubicacion': {
          'lat': position.latitude,
          'lng': position.longitude,
          'address': address ?? '',
          'lastUpdated': FieldValue.serverTimestamp(),
        },
      });
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
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'conductor.lat': position.latitude,
        'conductor.lng': position.longitude,
        'conductor.lastUpdated': FieldValue.serverTimestamp(),
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
    return _firestore
        .collection('conductor')
        .doc(conductorId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      final ubicacion = data['ubicacion'];
      if (ubicacion is! Map) return null;

      final lat = ubicacion['lat'] ?? ubicacion['latitude'];
      final lng = ubicacion['lng'] ?? ubicacion['longitude'] ?? ubicacion['longitud'];

      if (lat == null || lng == null) return null;

      return LatLng(
        (lat as num).toDouble(),
        (lng as num).toDouble(),
      );
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

      final lat = conductor['lat'] ?? conductor['latitude'];
      final lng = conductor['lng'] ?? conductor['longitude'];

      if (lat == null || lng == null) return null;

      return LatLng(
        (lat as num).toDouble(),
        (lng as num).toDouble(),
      );
    });
  }

  /// Escucha cambios en la ubicación de un cliente en tiempo real.
  ///
  /// Retorna un Stream que emite [LatLng] cada vez que cambia la ubicación.
  Stream<LatLng?> escucharUbicacionCliente(String clienteId) {
    return _firestore
        .collection('cliente')
        .doc(clienteId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      if (data == null) return null;

      final ubicacion = data['ubicacion'];
      if (ubicacion is! Map) return null;

      final lat = ubicacion['lat'] ?? ubicacion['latitude'];
      final lng = ubicacion['lng'] ?? ubicacion['longitude'];

      if (lat == null || lng == null) return null;

      return LatLng(
        (lat as num).toDouble(),
        (lng as num).toDouble(),
      );
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
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'status': nuevoEstado,
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
  /// Actualiza el estado a 'en_progreso' y registra la hora de inicio.
  Future<void> iniciarViaje(String solicitudId) async {
    try {
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'status': 'en_progreso',
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error al iniciar el viaje: $e');
    }
  }

  /// Finaliza un viaje exitosamente.
  ///
  /// Actualiza el estado a 'completado' y registra la hora de finalización.
  Future<void> finalizarViaje(String solicitudId) async {
    try {
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'status': 'completado',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
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
      final updateData = {
        'status': 'cancelado',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (razon != null) {
        updateData['cancelReason'] = razon;
      }
      if (canceladoPor != null) {
        updateData['cancelledBy'] = canceladoPor;
      }

      await _firestore.collection('solicitudes').doc(solicitudId).update(updateData);
    } catch (e) {
      throw Exception('Error al cancelar el viaje: $e');
    }
  }

  /// Asigna un conductor a una solicitud y actualiza el estado a 'asignado'.
  ///
  /// [solicitudId] - ID de la solicitud.
  /// [conductorId] - ID del conductor asignado.
  /// [conductorData] - Datos adicionales del conductor (nombre, foto, placa, etc.).
  Future<void> asignarConductor({
    required String solicitudId,
    required String conductorId,
    Map<String, dynamic>? conductorData,
  }) async {
    try {
      final updateData = {
        'status': 'asignado',
        'conductorId': conductorId,
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (conductorData != null) {
        updateData['conductor'] = conductorData;
      }

      await _firestore.collection('solicitudes').doc(solicitudId).update(updateData);
    } catch (e) {
      throw Exception('Error al asignar conductor: $e');
    }
  }

  /// Obtiene el estado completo de una solicitud como snapshot único.
  ///
  /// Útil para obtener información detallada sin suscripciones en tiempo real.
  Future<Map<String, dynamic>?> obtenerEstadoSolicitud(String solicitudId) async {
    try {
      final doc = await _firestore.collection('solicitudes').doc(solicitudId).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      throw Exception('Error al obtener estado de la solicitud: $e');
    }
  }
}
