// Cobertura de la lógica pura del panel admin — antes `admin_home_screen.dart`
// no tenía ningún test. Fija los bugs encontrados en la auditoría: docs con
// `tipoUsuario` en vez de `rol`, roles inesperados que desaparecían de ambas
// pestañas, y una búsqueda que no encontraba por teléfono ni placa.

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/features/admin/admin_usuario_filtros.dart';

void main() {
  group('clasificarUsuario', () {
    test('rol == conductor va a conductor', () {
      expect(
        clasificarUsuario({'rol': 'conductor'}),
        AdminUserBucket.conductor,
      );
    });

    test('rol vacío o cliente va a cliente', () {
      expect(clasificarUsuario({'rol': 'cliente'}), AdminUserBucket.cliente);
      expect(clasificarUsuario({}), AdminUserBucket.cliente);
    });

    test(
      'tipoUsuario == conductor con rol vacío va a conductor '
      '(antes caía en Clientes por ignorar este campo)',
      () {
        expect(
          clasificarUsuario({'tipoUsuario': 'conductor'}),
          AdminUserBucket.conductor,
        );
      },
    );

    test('solicitudConductor == true va a conductor aunque rol sea cliente', () {
      expect(
        clasificarUsuario({'rol': 'cliente', 'solicitudConductor': true}),
        AdminUserBucket.conductor,
      );
    });

    test(
      'rol == admin no desaparece del panel: cae en cliente, no en ningún '
      'balde inexistente (antes ni conductores ni clientes lo mostraba)',
      () {
        expect(clasificarUsuario({'rol': 'admin'}), AdminUserBucket.cliente);
      },
    );
  });

  group('coincideBusqueda', () {
    test('query vacía matchea todo', () {
      expect(coincideBusqueda({'nombre': 'Ana'}, ''), isTrue);
    });

    test('busca por nombre y apellido en cualquier orden', () {
      final data = {'nombre': 'Ana', 'apellido': 'Martínez'};
      expect(coincideBusqueda(data, 'Ana Martinez'), isTrue);
      expect(coincideBusqueda(data, 'Martinez'), isTrue);
    });

    test('ignora acentos', () {
      expect(
        coincideBusqueda({'nombre': 'José', 'apellido': 'Pérez'}, 'jose perez'),
        isTrue,
      );
    });

    test('busca por teléfono ignorando +57, espacios y guiones', () {
      final data = {'telefono': '+57 300-123-4567'};
      expect(coincideBusqueda(data, '3001234567'), isTrue);
      expect(coincideBusqueda(data, '300-123-4567'), isTrue);
    });

    test('busca por placa ignorando mayúsculas y guion', () {
      final data = {'placa': 'ABC-123'};
      expect(coincideBusqueda(data, 'abc123'), isTrue);
      expect(coincideBusqueda(data, 'ABC-123'), isTrue);
    });

    test('no matchea cuando no coincide nada', () {
      final data = {
        'nombre': 'Ana',
        'apellido': 'Martínez',
        'telefono': '3001234567',
        'placa': 'ABC123',
      };
      expect(coincideBusqueda(data, 'zzz'), isFalse);
    });
  });
}
