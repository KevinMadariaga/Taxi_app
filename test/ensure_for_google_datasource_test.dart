// Regresión: `ClientUserFirestoreDataSource.ensureForGoogle` es el único
// punto que escribe `nombre`/`apellido` desde el `displayName` que trae el
// login de Google/Apple. Este candado fija el contrato: en un alta nueva sí
// se prellena desde el proveedor, pero en un usuario que ya tiene nombre
// guardado, el `displayName` de Gmail/Apple NUNCA debe pisar lo que el
// usuario ya editó.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/client_user_firestore_datasource.dart';

const _uid = 'cliente-1';

void main() {
  group('ClientUserFirestoreDataSource.ensureForGoogle', () {
    test(
      'doc existente con nombre ya editado: el displayName de Gmail se ignora',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('usuarios').doc(_uid).set({
          'nombre': 'Juan',
          'apellido': 'Editado',
          'rol': 'cliente',
        });
        final datasource = ClientUserFirestoreDataSource(firestore: firestore);

        final result = await datasource.ensureForGoogle(
          uid: _uid,
          displayName: 'Gmail Default',
          email: 'gmail-default@example.com',
        );

        expect(result.nombre, 'Juan');
        expect(result.apellido, 'Editado');

        final doc = await firestore.collection('usuarios').doc(_uid).get();
        expect(doc.data()?['nombre'], 'Juan');
        expect(doc.data()?['apellido'], 'Editado');
      },
    );

    // Carrera: FcmService guardó el token antes que el perfil, así que el
    // doc existía solo con `fcmToken`. Antes se trataba como cuenta vieja y
    // quedaba sin `rol` ni `createdAt` (sin aviso de cliente nuevo al admin
    // ni etiqueta "Nuevo" en el panel).
    test('doc con solo el token FCM: se trata como alta nueva', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({
        'fcmToken': 'token-1',
      });
      final datasource = ClientUserFirestoreDataSource(firestore: firestore);

      await datasource.ensureForGoogle(
        uid: _uid,
        displayName: 'Ana López',
        email: 'ana@example.com',
      );

      final data = (await firestore.collection('usuarios').doc(_uid).get())
          .data();
      expect(data?['rol'], 'cliente');
      expect(data?['createdAt'], isNotNull);
      expect(data?['nombre'], 'Ana');
      expect(data?['fcmToken'], 'token-1', reason: 'el token se conserva');
    });

    test(
      'cuenta vieja sin rol pero con teléfono y foto: NO se reescribe',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('usuarios').doc(_uid).set({
          'nombre': 'Rosa',
          'telefono': '3001234567',
          'foto': 'https://foto',
          'isProfileComplete': true,
          'fcmToken': 't',
        });
        final datasource = ClientUserFirestoreDataSource(firestore: firestore);

        await datasource.ensureForGoogle(
          uid: _uid,
          displayName: 'Otro Nombre',
          email: 'rosa@example.com',
        );

        final data = (await firestore.collection('usuarios').doc(_uid).get())
            .data();
        expect(data?['telefono'], '3001234567');
        expect(data?['foto'], 'https://foto');
        expect(data?['isProfileComplete'], true);
        expect(data?['nombre'], 'Rosa');
      },
    );

    test('doc inexistente: sí se prellena partiendo el displayName', () async {
      final firestore = FakeFirebaseFirestore();
      final datasource = ClientUserFirestoreDataSource(firestore: firestore);

      final result = await datasource.ensureForGoogle(
        uid: _uid,
        displayName: 'Juan Carlos Pérez',
        email: 'juan@example.com',
      );

      expect(result.nombre, 'Juan');
      expect(result.apellido, 'Carlos Pérez');

      final doc = await firestore.collection('usuarios').doc(_uid).get();
      expect(doc.data()?['nombre'], 'Juan');
      expect(doc.data()?['apellido'], 'Carlos Pérez');
      expect(doc.data()?['isProfileComplete'], false);
    });

    test('doc existente pero con nombre vacío (alta previa fallida): backfill '
        'desde el displayName', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({
        'nombre': '',
        'apellido': '',
        'rol': 'cliente',
      });
      final datasource = ClientUserFirestoreDataSource(firestore: firestore);

      final result = await datasource.ensureForGoogle(
        uid: _uid,
        displayName: 'Ana López',
        email: 'ana@example.com',
      );

      expect(result.nombre, 'Ana');
      expect(result.apellido, 'López');
    });
  });
}
