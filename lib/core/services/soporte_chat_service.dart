import 'package:cloud_firestore/cloud_firestore.dart';

class SoporteChatService {
  SoporteChatService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _chatRef(String userId) =>
      _firestore.collection('soporte_chats').doc(userId);

  CollectionReference<Map<String, dynamic>> _mensajesRef(String userId) =>
      _chatRef(userId).collection('mensajes');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMensajes(String userId) {
    return _mensajesRef(
      userId,
    ).orderBy('creadoEn', descending: false).snapshots();
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

    batch.set(_chatRef(userId), {
      'userId': userId,
      'userName': userName,
      'userType': userType,
      'ultimoMensaje': texto.trim(),
      'ultimoMensajeAt': FieldValue.serverTimestamp(),
      'hayMensajesNuevosAdmin': !esAdmin,
    }, SetOptions(merge: true));

    await batch.commit();

    // El push a los admins ya no lo manda el cliente (auditoría de
    // seguridad: `AdminFcmService` usaba la server key legacy de FCM
    // repartida a todos los dispositivos vía Remote Config). Lo dispara
    // `onSoporteChatMensajeUsuarioCreado` en functions/index.js al ver este
    // mismo mensaje en Firestore.
  }

  /// `set` con merge y no `update`: `update` falla si el chat todavía no
  /// existe, y el admin lo llama sin esperar al abrir el chat.
  Future<void> marcarLeidoPorAdmin(String userId) {
    return _chatRef(
      userId,
    ).set({'hayMensajesNuevosAdmin': false}, SetOptions(merge: true));
  }

  /// Empieza una conversación nueva para el usuario SIN borrar mensajes.
  ///
  /// Antes borraba todos los mensajes en un batch, pero las reglas no
  /// permiten borrarlos (son el registro de los reportes de seguridad para
  /// soporte): el batch completo fallaba con `permission-denied` y la app se
  /// cerraba. Ahora se marca `inicioConversacion` y la pantalla del usuario
  /// muestra solo los mensajes desde ahí; el admin conserva el historial.
  ///
  /// Devuelve la marca tal como la guardó el servidor, para filtrar con el
  /// mismo reloj con el que se sellan los mensajes (`creadoEn`).
  Future<DateTime?> resetearChat(String userId) async {
    await _chatRef(userId).set({
      'inicioConversacion': FieldValue.serverTimestamp(),
      'ultimoMensaje': '',
      'hayMensajesNuevosAdmin': false,
      'ultimoMensajeAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return inicioConversacion(userId);
  }

  /// Desde cuándo mostrarle mensajes al usuario (`null` = todos).
  Future<DateTime?> inicioConversacion(String userId) async {
    final doc = await _chatRef(userId).get();
    final ts = doc.data()?['inicioConversacion'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  /// Si el mensaje [data] pertenece a la conversación que empezó en [desde].
  /// Un mensaje recién enviado todavía sin `creadoEn` (pendiente del
  /// servidor) se muestra.
  static bool esDeConversacionActual(
    Map<String, dynamic> data,
    DateTime? desde,
  ) {
    if (desde == null) return true;
    final ts = data['creadoEn'];
    if (ts is! Timestamp) return true;
    return !ts.toDate().isBefore(desde);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTodosChats() {
    return _firestore
        .collection('soporte_chats')
        .orderBy('ultimoMensajeAt', descending: true)
        .snapshots();
  }

  /// Cantidad de chats con mensajes nuevos sin leer por el admin (badge de
  /// `AdminHubScreen`).
  Stream<int> watchChatsConMensajesNuevosCount() {
    return _firestore
        .collection('soporte_chats')
        .where('hayMensajesNuevosAdmin', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
