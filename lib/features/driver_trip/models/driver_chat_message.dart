import 'package:cloud_firestore/cloud_firestore.dart';

class DriverChatMessage {
  const DriverChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.readBy,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime? timestamp;
  final Map<String, bool> readBy;

  bool isReadBy(String userId) => readBy[userId] == true;

  factory DriverChatMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['timestamp'];

    return DriverChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      text: (data['texto'] ?? '').toString(),
      timestamp: ts is Timestamp ? ts.toDate() : null,
      readBy: (data['readBy'] as Map<String, dynamic>? ?? <String, dynamic>{})
          .map((key, value) => MapEntry(key, value == true)),
    );
  }
}
