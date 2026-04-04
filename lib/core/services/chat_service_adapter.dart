import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/chat_service.dart'
    as feature_chat;
import 'package:taxi_app/features/trip_tracking_cliente/models/mensaje_model.dart'
    as feature_model;

/// Compatibility adapter exposing the legacy ChatService API and delegating
/// to the newer feature ChatService implementation.
class ChatService {
  final feature_chat.ChatService _inner;

  ChatService({FirebaseFirestore? db, feature_chat.ChatService? inner})
    : _inner = inner ?? feature_chat.ChatService(firestore: db);

  Stream<List<ChatMessage>> listenMessages(String solicitudId) {
    return _inner.watchMessages(solicitudId).map((list) {
      return list
          .map(
            (m) => ChatMessage(
              id: m.id,
              senderId: m.senderId,
              texto: m.texto,
              timestamp: m.timestamp,
              readBy: m.readBy,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> sendMessage({
    required String solicitudId,
    required String senderId,
    required String texto,
  }) async {
    await _inner.sendMessage(
      solicitudId: solicitudId,
      senderId: senderId,
      texto: texto,
    );
  }

  Future<void> markMessageRead({
    required String solicitudId,
    required String messageId,
    required String userId,
  }) async {
    await _inner.markAsRead(
      solicitudId: solicitudId,
      messageId: messageId,
      userId: userId,
    );
  }

  Future<void> markAllAsRead({
    required String solicitudId,
    required String userId,
    required List<ChatMessage> messages,
  }) async {
    final converted = messages
        .map(
          (m) => feature_model.MensajeModel(
            id: m.id,
            senderId: m.senderId,
            texto: m.texto,
            timestamp: m.timestamp,
            readBy: m.readBy,
          ),
        )
        .toList(growable: false);
    await _inner.markAllAsRead(
      solicitudId: solicitudId,
      userId: userId,
      messages: converted,
    );
  }
}
