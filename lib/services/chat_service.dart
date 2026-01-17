import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';


class ChatService {
  final FirebaseFirestore _db;
  ChatService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _mensajesRef(String solicitudId) =>
      _db.collection('solicitudes').doc(solicitudId).collection('mensajes');

  Stream<List<ChatMessage>> listenMessages(String solicitudId) {
    return _mensajesRef(solicitudId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatMessage.fromDoc(d)).toList());
  }

  Future<void> sendMessage({
    required String solicitudId,
    required String senderId,
    required String texto,
  }) async {
    if (texto.trim().isEmpty) return;
    await _mensajesRef(solicitudId).add({
      'senderId': senderId,
      'texto': texto.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {senderId: true},
    });
  }

  Future<void> markMessageRead({
    required String solicitudId,
    required String messageId,
    required String userId,
  }) async {
    await _mensajesRef(
      solicitudId,
    ).doc(messageId).update({'readBy.$userId': true});
  }
}
