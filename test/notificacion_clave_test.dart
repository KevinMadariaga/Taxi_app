import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';

/// La mitad Dart del contrato con `functions/notificaciones.js`.
///
/// La app cancela una notificación por su id entero, y para los avisos que
/// llegan por FCM ese id lo calcula el backend. Si el hash cambia de un solo
/// lado, retirar una notificación deja de funcionar y **nada falla a la
/// vista**: se descubriría en producción, con la bandeja del conductor llena
/// de solicitudes que ya no existen. Estos vectores son lo único que ata las
/// dos implementaciones.
void main() {
  // Los MISMOS pares están en `functions/notificaciones.test.js`.
  const vectores = <String, int>{
    'nueva_solicitud_cli123': 1645069590,
    'viaje_solABC': 448669161,
    'chat_solABC': 1848650506,
    'general': 616112491,
  };

  group('idNotificacion', () {
    test('respeta los vectores del contrato con el backend', () {
      vectores.forEach((clave, esperado) {
        expect(idNotificacion(clave), esperado, reason: 'clave: $clave');
      });
    });

    test('es estable y cabe en un int32 con signo', () {
      for (final clave in ['a', 'nueva_solicitud_xyz', 'x' * 64]) {
        final id = idNotificacion(clave);
        expect(id, idNotificacion(clave));
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7fffffff));
      }
    });

    test('claves distintas dan ids distintos en los casos que usamos', () {
      final claves = [
        claveNotificacion('nueva_solicitud', 'cli1'),
        claveNotificacion('nueva_solicitud', 'cli2'),
        claveNotificacion('trip_status_change', 'sol1'),
        claveNotificacion('trip_chat_message', 'sol1'),
        claveNotificacion('payment_method_change', 'sol1'),
      ];
      expect(claves.map(idNotificacion).toSet(), hasLength(claves.length));
    });
  });

  group('claveNotificacion', () {
    test('arma <tipo>_<entidad> y sanea la entrada', () {
      expect(
        claveNotificacion('nueva_solicitud', 'cli123'),
        'nueva_solicitud_cli123',
      );
      expect(claveNotificacion('chat', 'sol/../otro'), 'chat_solotro');
      expect(claveNotificacion('tipo', '  con espacios  '), 'tipo_conespacios');
    });

    test('tolera entidad ausente', () {
      expect(claveNotificacion('emergencia'), 'emergencia');
      expect(claveNotificacion('emergencia', ''), 'emergencia');
      expect(claveNotificacion('emergencia', null), 'emergencia');
      expect(claveNotificacion(''), 'general');
    });

    test('corta a 64 bytes, el límite de apns-collapse-id', () {
      final clave = claveNotificacion('trip_status_change', 'x' * 200);
      // El string EXACTO, no solo el largo: el backend corta por bytes UTF-8
      // y esto por caracteres UTF-16, así que hay que fijar el resultado y no
      // una propiedad que ambos cumplirían aun cortando distinto.
      expect(clave, 'trip_status_change_${'x' * 45}');
      expect(clave.length, maxClaveBytes);
    });

    test('el saneado deja solo ASCII', () {
      // De eso depende que el hash coincida con el del backend: allá se
      // recorren BYTES UTF-8 y acá code units UTF-16, que solo son lo mismo
      // mientras no entre un carácter fuera de ASCII.
      final clave = claveNotificacion('tipo', 'ñandú-über_123');
      expect(clave, 'tipo_and-ber_123');
      expect(clave.codeUnits.every((c) => c < 128), isTrue);
    });
  });

  test('idNotificacionDe compone las dos funciones', () {
    expect(
      idNotificacionDe('nueva_solicitud', 'cli123'),
      idNotificacion('nueva_solicitud_cli123'),
    );
  });
}
