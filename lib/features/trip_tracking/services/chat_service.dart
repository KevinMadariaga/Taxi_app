import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/mensaje_model.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messagesRef(String solicitudId) {
    return _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .collection('mensajes');
  }

  Stream<List<MensajeModel>> watchMessages(String solicitudId) {
    return _messagesRef(solicitudId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs.map(MensajeModel.fromDoc).toList(growable: false),
        );
  }

  Stream<int> watchUnreadCount({
    required String solicitudId,
    required String userId,
  }) {
    return watchMessages(solicitudId).map((messages) {
      return messages
          .where((m) => m.senderId != userId && !m.isReadBy(userId))
          .length;
    });
  }

  Future<void> sendMessage({
    required String solicitudId,
    required String senderId,
    required String texto,
  }) async {
    final clean = texto.trim();
    if (clean.isEmpty) return;

    await _messagesRef(solicitudId).add({
      'senderId': senderId,
      'texto': clean,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {senderId: true},
    });
  }

  Future<void> markAsRead({
    required String solicitudId,
    required String messageId,
    required String userId,
  }) {
    return _messagesRef(
      solicitudId,
    ).doc(messageId).update({'readBy.$userId': true});
  }

  Future<void> markAllAsRead({
    required String solicitudId,
    required String userId,
    required List<MensajeModel> messages,
  }) async {
    final pending = messages.where(
      (m) => m.senderId != userId && !m.isReadBy(userId),
    );

    final batch = _firestore.batch();
    for (final message in pending) {
      batch.update(_messagesRef(solicitudId).doc(message.id), {
        'readBy.$userId': true,
      });
    }

    await batch.commit();
  }
}
