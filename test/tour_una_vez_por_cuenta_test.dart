import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/caracteristicas/tour_introductorio/datos/tour_repository_impl.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cuenta nueva: no lo ha visto', () async {
    final repo = TourRepositoryImpl(firestore: FakeFirebaseFirestore());
    expect(await repo.yaVisto('inicio_cliente_v1', 'u1'), isFalse);
  });

  test(
    'una vez visto, no vuelve a salir ni en otro teléfono / reinstalado',
    () async {
      final db = FakeFirebaseFirestore();
      await TourRepositoryImpl(
        firestore: db,
      ).marcarVisto('inicio_cliente_v1', 'u1');
      await Future<void>.delayed(Duration.zero); // deja subir el set

      // Otro teléfono o app reinstalada: caché local vacía.
      SharedPreferences.setMockInitialValues({});
      final enOtroTelefono = TourRepositoryImpl(firestore: db);
      expect(await enOtroTelefono.yaVisto('inicio_cliente_v1', 'u1'), isTrue);

      final doc = await db.collection('usuarios').doc('u1').get();
      expect(
        (doc.data()?['toursVistos'] as Map).containsKey('inicio_cliente_v1'),
        isTrue,
      );
    },
  );

  test('cada recorrido y cada cuenta por separado', () async {
    final db = FakeFirebaseFirestore();
    final repo = TourRepositoryImpl(firestore: db);
    await repo.marcarVisto('inicio_cliente_v1', 'u1');
    await Future<void>.delayed(Duration.zero);

    expect(await repo.yaVisto('inicio_conductor_v1', 'u1'), isFalse);
    expect(await repo.yaVisto('inicio_cliente_v1', 'u2'), isFalse);
  });
}
