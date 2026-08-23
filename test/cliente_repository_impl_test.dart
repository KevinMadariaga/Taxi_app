// Regresión: `ClienteRepositoryImpl.obtenerActual()` resolvía el nombre del
// cliente priorizando `FirebaseAuth.currentUser.displayName` (el que puso
// Google/Apple al registrarse, congelado para siempre) por encima del
// `nombre`/`apellido` de `usuarios/{uid}` en Firestore (el que sí se
// actualiza cuando el cliente edita su perfil). Un cliente que editaba su
// nombre en la app seguía apareciéndole al conductor con el nombre viejo de
// Google/Apple en la preview de la solicitud.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/datos/repositorios/cliente_repository_impl.dart';

import 'test_helpers/firebase_test_setup.dart';

const _uid = 'cliente-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupFirebaseForTests();
  });

  group('ClienteRepositoryImpl.obtenerActual — resolución de nombre', () {
    test(
      'usa el nombre actual de Firestore, no el displayName viejo de Auth',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('usuarios').doc(_uid).set({
          'nombre': 'Carlos',
          'apellido': 'Nuevo',
        });
        final repo = ClienteRepositoryImpl(
          auth: MockFirebaseAuth(
            signedIn: true,
            // Nombre que puso Google al registrarse — el cliente ya lo
            // cambió en su perfil, pero Auth nunca se entera.
            mockUser: MockUser(uid: _uid, displayName: 'Carlos Viejo Google'),
          ),
          firestore: firestore,
        );

        final actual = await repo.obtenerActual();

        expect(actual?.nombre, 'Carlos Nuevo');
      },
    );

    test('sin doc en Firestore, cae al displayName de Auth', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ClienteRepositoryImpl(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _uid, displayName: 'Solo Auth'),
        ),
        firestore: firestore,
      );

      final actual = await repo.obtenerActual();

      expect(actual?.nombre, 'Solo Auth');
    });

    test('sin nombre en ningún lado, cae al email', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = ClienteRepositoryImpl(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _uid, email: 'juan.perez@gmail.com'),
        ),
        firestore: firestore,
      );

      final actual = await repo.obtenerActual();

      expect(actual?.nombre, 'Juan Perez');
    });
  });
}
