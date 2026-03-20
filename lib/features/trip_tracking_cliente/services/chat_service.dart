import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/core/services/chat_firestore_datasource.dart';

import '../models/mensaje_model.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, ChatFirestoreDatasource? datasource})
      : _firestoreOverride = firestore,
        _datasource = datasource ?? ChatFirestoreDatasource(firestore: firestore);

  final FirebaseFirestore? _firestoreOverride;
  final ChatFirestoreDatasource _datasource;

  FirebaseFirestore get _firestore {
    if (_firestoreOverride != null) {
      return _firestoreOverride;
    }

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar ChatService.',
      );
    }

    return FirebaseFirestore.instance;
  }

  Stream<List<MensajeModel>> watchMessages(String solicitudId) {
    return _datasource
        .watchOrderedMessages(solicitudId)
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
    await _datasource.sendMessage(
      solicitudId: solicitudId,
      senderId: senderId,
      texto: texto,
    );
  }

  Future<void> markAsRead({
    required String solicitudId,
    required String messageId,
    required String userId,
  }) {
    return _datasource.markMessageRead(
      solicitudId: solicitudId,
      messageId: messageId,
      userId: userId,
    );
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
      batch.update(_datasource.messagesRef(solicitudId).doc(message.id), {
        'readBy.$userId': true,
      });
    }

    await batch.commit();
  }
}
