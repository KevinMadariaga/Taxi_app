import 'package:cloud_firestore/cloud_firestore.dart';

class MensajeModel {
  final String id;
  final String senderId;
  final String texto;
  final DateTime? timestamp;
  final Map<String, bool> readBy;

  const MensajeModel({
    required this.id,
    required this.senderId,
    required this.texto,
    required this.timestamp,
    required this.readBy,
  });

  factory MensajeModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['timestamp'];

    return MensajeModel(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      texto: (data['texto'] ?? '').toString(),
      timestamp: ts is Timestamp ? ts.toDate() : null,
      readBy: (data['readBy'] as Map<String, dynamic>? ?? <String, dynamic>{})
          .map((key, value) => MapEntry(key, value == true)),
    );
  }

  factory MensajeModel.fromMap(Map<String, dynamic> data) {
    final ts = data['timestamp'];
    return MensajeModel(
      id: (data['id'] ?? '').toString(),
      senderId: (data['senderId'] ?? '').toString(),
      texto: (data['texto'] ?? '').toString(),
      timestamp: ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
      readBy: (data['readBy'] as Map<String, dynamic>? ?? <String, dynamic>{})
          .map((key, value) => MapEntry(key, value == true)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'texto': texto,
      'timestamp': timestamp?.millisecondsSinceEpoch,
      'readBy': readBy,
    };
  }

  bool isReadBy(String userId) => readBy[userId] == true;
}
