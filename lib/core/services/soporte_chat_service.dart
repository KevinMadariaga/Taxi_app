import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_fcm_service.dart';

class SoporteChatService {
  SoporteChatService() : _firestore = FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _chatRef(String userId) =>
      _firestore.collection('soporte_chats').doc(userId);

  CollectionReference<Map<String, dynamic>> _mensajesRef(String userId) =>
      _chatRef(userId).collection('mensajes');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMensajes(String userId) {
    return _mensajesRef(userId)
        .orderBy('creadoEn', descending: false)
        .snapshots();
  }

  Future<void> sendMensaje({
    required String userId,
    required String userName,
    required String userType,
    required String texto,
    required bool esAdmin,
  }) async {
    final batch = _firestore.batch();

    final msgRef = _mensajesRef(userId).doc();
    batch.set(msgRef, {
      'texto': texto.trim(),
      'esAdmin': esAdmin,
      'creadoEn': FieldValue.serverTimestamp(),
    });

    batch.set(
      _chatRef(userId),
      {
        'userId': userId,
        'userName': userName,
        'userType': userType,
        'ultimoMensaje': texto.trim(),
        'ultimoMensajeAt': FieldValue.serverTimestamp(),
        'hayMensajesNuevosAdmin': !esAdmin,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!esAdmin) {
      AdminFcmService.instance.sendToAllAdmins(
        title: 'Soporte — $userName',
        body: texto.trim(),
        type: 'soporte_chat',
      );
    }
  }

  Future<void> marcarLeidoPorAdmin(String userId) {
    return _chatRef(userId).update({'hayMensajesNuevosAdmin': false});
  }

  /// Elimina todos los mensajes y resetea el metadata del chat.
  Future<void> resetearChat(String userId) async {
    final mensajes = await _mensajesRef(userId).get();
    final batch = _firestore.batch();
    for (final doc in mensajes.docs) {
      batch.delete(doc.reference);
    }
    batch.set(
      _chatRef(userId),
      {
        'ultimoMensaje': '',
        'hayMensajesNuevosAdmin': false,
        'ultimoMensajeAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTodosChats() {
    return _firestore
        .collection('soporte_chats')
        .orderBy('ultimoMensajeAt', descending: true)
        .snapshots();
  }
}
