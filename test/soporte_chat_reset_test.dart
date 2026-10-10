import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';

void main() {
  // Crashlytics: "permission-denied" en writeBatchCommit. "Nueva
  // conversación" borraba los mensajes en un batch y las reglas no permiten
  // borrarlos (`allow update, delete: if false`).
  test('nueva conversación no borra mensajes: marca el inicio', () async {
    final db = FakeFirebaseFirestore();
    final servicio = SoporteChatService(firestore: db);
    await servicio.sendMensaje(
      userId: 'u1',
      userName: 'Ana',
      userType: 'cliente',
      texto: 'hola',
      esAdmin: false,
    );

    final desde = await servicio.resetearChat('u1');

    final mensajes = await db
        .collection('soporte_chats')
        .doc('u1')
        .collection('mensajes')
        .get();
    expect(mensajes.docs, hasLength(1), reason: 'el historial se conserva');
    expect(desde, isNotNull);
    expect(await servicio.inicioConversacion('u1'), desde);
  });

  test('la pantalla solo muestra la conversación actual', () {
    final desde = DateTime(2026, 10, 5, 12);
    Map<String, dynamic> msg(DateTime? t) => {
      'texto': 'x',
      if (t != null) 'creadoEn': Timestamp.fromDate(t),
    };

    expect(
      SoporteChatService.esDeConversacionActual(
        msg(desde.subtract(const Duration(minutes: 1))),
        desde,
      ),
      isFalse,
    );
    expect(
      SoporteChatService.esDeConversacionActual(
        msg(desde.add(const Duration(minutes: 1))),
        desde,
      ),
      isTrue,
    );
    // Recién enviado, aún sin sello del servidor: se muestra.
    expect(SoporteChatService.esDeConversacionActual(msg(null), desde), isTrue);
    // Sin conversación nueva: se muestra todo.
    expect(
      SoporteChatService.esDeConversacionActual(msg(DateTime(2020)), null),
      isTrue,
    );
  });
}
