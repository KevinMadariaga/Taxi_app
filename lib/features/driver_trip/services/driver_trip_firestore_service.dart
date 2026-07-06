import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/driver_chat_message.dart';
import '../models/driver_trip_model.dart';

class DriverTripFirestoreService {
  DriverTripFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _tripRef(String tripId) {
    return _firestore.collection('solicitudes').doc(tripId);
  }

  CollectionReference<Map<String, dynamic>> _messagesRef(String tripId) {
    return _tripRef(tripId).collection('mensajes');
  }

  Stream<DriverTripModel> watchTrip(String tripId) {
    return _tripRef(tripId).snapshots().map((doc) {
      if (!doc.exists) {
        throw StateError('Solicitud no existe: $tripId');
      }
      return DriverTripModel.fromDoc(doc);
    });
  }

  /// Lectura puntual (no-stream) del viaje, forzando servidor cuando hay red.
  /// Se usa al volver de background: el listener en vivo puede haberse
  /// suspendido con la app (pantalla bloqueada u otra app en primer plano) y
  /// perder el evento de cancelación; esto reconcilia el estado real aunque
  /// el stream no haya entregado el cambio.
  Future<DriverTripModel?> fetchTripOnce(String tripId) async {
    try {
      final doc = await _tripRef(
        tripId,
      ).get(const GetOptions(source: Source.serverAndCache));
      if (!doc.exists) return null;
      return DriverTripModel.fromDoc(doc);
    } catch (_) {
      return null;
    }
  }

  Stream<List<DriverChatMessage>> watchMessages(String tripId) {
    return _messagesRef(tripId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(DriverChatMessage.fromDoc).toList(growable: false),
        );
  }

  Future<void> sendMessage({
    required String tripId,
    required String senderId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    await _messagesRef(tripId).add({
      'senderId': senderId,
      'texto': clean,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {senderId: true},
    });
  }

  Future<void> markAllMessagesAsRead({
    required String tripId,
    required String userId,
    required List<DriverChatMessage> messages,
  }) async {
    final pending = messages.where(
      (m) => m.senderId != userId && !m.isReadBy(userId),
    );

    final batch = _firestore.batch();
    for (final msg in pending) {
      batch.update(_messagesRef(tripId).doc(msg.id), {'readBy.$userId': true});
    }
    await batch.commit();
  }

  Future<void> updateTripStatus({
    required String tripId,
    required String status,
  }) {
    final payload = <String, dynamic>{
      'estado': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    return _tripRef(tripId).set(payload, SetOptions(merge: true));
  }

  Future<void> updateDriverLocation({
    required String tripId,
    required LatLng position,
  }) {
    // Free-tier write path in Firestore. Keep payload compact to reduce write size.
    return _tripRef(tripId).set({
      'conductor': {
        'lat': position.latitude,
        'lng': position.longitude,
        'ubicacion': {'lat': position.latitude, 'lng': position.longitude},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
