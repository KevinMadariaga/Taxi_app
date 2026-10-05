import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/modelos/contacto_emergencia.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';

const _mama = ContactoEmergencia(nombre: 'Mamá', telefono: '3001234567');

void main() {
  group('ContactoEmergencia', () {
    test('normaliza el teléfono: solo dígitos y sin el 57', () {
      expect(
        ContactoEmergencia.normalizarTelefono('300 123 4567'),
        '3001234567',
      );
      expect(
        ContactoEmergencia.normalizarTelefono('+57 300-123-4567'),
        '3001234567',
      );
    });

    test('valida nombre y teléfono', () {
      expect(ContactoEmergencia.validarNombre(''), isNotNull);
      expect(ContactoEmergencia.validarNombre('A'), isNotNull);
      expect(ContactoEmergencia.validarNombre('Mamá'), isNull);
      expect(ContactoEmergencia.validarTelefono(''), isNotNull);
      expect(ContactoEmergencia.validarTelefono('300123'), isNotNull);
      expect(ContactoEmergencia.validarTelefono('3001234567'), isNull);
    });

    test('lee el formato viejo (un solo texto con nombre y número)', () {
      final c = ContactoEmergencia.desdeFirestore('Mamá 300 123 4567');
      expect(c.nombre, 'Mamá');
      expect(c.telefono, '3001234567');
    });

    test('muestra el teléfono legible', () {
      expect(_mama.telefonoLegible, '300 123 4567');
    });
  });

  group('UserDataService contactos de emergencia', () {
    // Crashlytics: "Cannot add to an unmodifiable list" en
    // SeguridadView._agregarContacto al agregar el primer contacto.
    test('sin contactos guardados devuelve una lista modificable', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('usuarios').doc('u1').set({'rol': 'cliente'});

      final contactos = await UserDataService(
        firestore: db,
      ).obtenerContactosEmergencia('u1');

      expect(contactos, isEmpty);
      contactos.add(_mama);
      expect(contactos, [_mama]);
    });

    test('guarda nombre y teléfono por separado y los vuelve a leer', () async {
      final db = FakeFirebaseFirestore();
      final servicio = UserDataService(firestore: db);

      await servicio.guardarContactosEmergencia(uid: 'u1', contactos: [_mama]);

      final doc = await db.collection('usuarios').doc('u1').get();
      expect(doc.data()?['contactosEmergencia'], [
        {'nombre': 'Mamá', 'telefono': '3001234567'},
      ]);
      expect(await servicio.obtenerContactosEmergencia('u1'), [_mama]);
    });

    test('convierte los contactos viejos guardados como texto', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('usuarios').doc('u1').set({
        'contactosEmergencia': ['Papá 3109876543'],
      });

      final contactos = await UserDataService(
        firestore: db,
      ).obtenerContactosEmergencia('u1');

      expect(contactos, [
        const ContactoEmergencia(nombre: 'Papá', telefono: '3109876543'),
      ]);
    });
  });
}
