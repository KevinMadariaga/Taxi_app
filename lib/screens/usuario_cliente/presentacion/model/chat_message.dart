import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String texto;
  final DateTime? timestamp;
  final Map<String, bool> readBy;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.texto,
    required this.timestamp,
    required this.readBy,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      texto: (data['texto'] ?? '').toString(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      readBy: Map<String, bool>.from(data['readBy'] ?? const {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'texto': texto,
      'timestamp': Timestamp.fromDate(timestamp ?? DateTime.now()),
      'readBy': readBy,
    };
  }
}
