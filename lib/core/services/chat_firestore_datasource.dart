import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class ChatFirestoreDatasource {
  ChatFirestoreDatasource({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore {
    final override = _firestoreOverride;
    if (override != null) return override;

    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase no ha sido inicializado. Llama Firebase.initializeApp() antes de usar ChatFirestoreDatasource.',
      );
    }

    return FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> messagesRef(String solicitudId) {
    return _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .collection('mensajes');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrderedMessages(
    String solicitudId,
  ) {
    return messagesRef(solicitudId)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendMessage({
    required String solicitudId,
    required String senderId,
    required String texto,
  }) async {
    final clean = texto.trim();
    if (clean.isEmpty) return;

    await messagesRef(solicitudId).add({
      'senderId': senderId,
      'texto': clean,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {senderId: true},
    });
  }

  Future<void> markMessageRead({
    required String solicitudId,
    required String messageId,
    required String userId,
  }) {
    return messagesRef(solicitudId)
        .doc(messageId)
        .update({'readBy.$userId': true});
  }
}
