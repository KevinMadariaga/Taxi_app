import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

void main() {
  group('SolicitudEstado.normalize', () {
    test('normaliza variantes conocidas de cada estado', () {
      expect(SolicitudEstado.normalize('Buscando'), SolicitudEstado.buscando);
      expect(SolicitudEstado.normalize('pending'), SolicitudEstado.buscando);
      expect(SolicitudEstado.normalize('pendiente'), SolicitudEstado.buscando);
      expect(SolicitudEstado.normalize('assigned'), SolicitudEstado.asignado);
      expect(SolicitudEstado.normalize('ASIGNADO'), SolicitudEstado.asignado);
      expect(SolicitudEstado.normalize('en_espera'), SolicitudEstado.enEspera);
      expect(SolicitudEstado.normalize('en-camino'), SolicitudEstado.enCamino);
      expect(SolicitudEstado.normalize('en_ruta'), SolicitudEstado.enRuta);
      expect(SolicitudEstado.normalize('Completado'), SolicitudEstado.completado);
      expect(SolicitudEstado.normalize('finalizado'), SolicitudEstado.completado);
      expect(SolicitudEstado.normalize('cancelado'), SolicitudEstado.cancelado);
      expect(SolicitudEstado.normalize('anulada'), SolicitudEstado.cancelado);
      expect(
        SolicitudEstado.normalize('sin_respuesta'),
        SolicitudEstado.sinRespuesta,
      );
      expect(
        SolicitudEstado.normalize('no response'),
        SolicitudEstado.sinRespuesta,
      );
    });

    test('no confunde pendiente_cliente (contraoferta) con buscando', () {
      // Match exacto para 'pendiente'/'pending': un estado compuesto como
      // 'pendiente_cliente' no debe normalizarse a 'buscando'.
      expect(
        SolicitudEstado.normalize('pendiente_cliente'),
        isNot(SolicitudEstado.buscando),
      );
    });

    test('string vacío se normaliza a vacío', () {
      expect(SolicitudEstado.normalize(''), '');
      expect(SolicitudEstado.normalize('   '), '');
    });

    test('estado desconocido se devuelve normalizado pero sin mapear', () {
      // Regresión: 'en_progreso' (usado por FirebaseService.iniciarViaje)
      // no debe quedar en limbo — si esto falla, algún estado nuevo dejó de
      // mapear a una constante conocida y quedará invisible para
      // isSesionActiva/isTerminal.
      expect(SolicitudEstado.normalize('estado_inventado'), 'estado inventado');
      expect(SolicitudEstado.isSesionActiva('estado inventado'), isFalse);
      expect(SolicitudEstado.isTerminal('estado inventado'), isFalse);
    });
  });

  group('SolicitudEstado.isSesionActiva', () {
    test('solo asignado/en espera/en camino/en ruta cuentan como activos', () {
      expect(SolicitudEstado.isSesionActiva(SolicitudEstado.asignado), isTrue);
      expect(SolicitudEstado.isSesionActiva(SolicitudEstado.enEspera), isTrue);
      expect(SolicitudEstado.isSesionActiva(SolicitudEstado.enCamino), isTrue);
      expect(SolicitudEstado.isSesionActiva(SolicitudEstado.enRuta), isTrue);
      expect(SolicitudEstado.isSesionActiva(SolicitudEstado.buscando), isFalse);
      expect(
        SolicitudEstado.isSesionActiva(SolicitudEstado.completado),
        isFalse,
      );
    });
  });

  group('SolicitudEstado.isTerminal', () {
    test('solo cancelado/completado/sin respuesta son terminales', () {
      expect(SolicitudEstado.isTerminal(SolicitudEstado.cancelado), isTrue);
      expect(SolicitudEstado.isTerminal(SolicitudEstado.completado), isTrue);
      expect(SolicitudEstado.isTerminal(SolicitudEstado.sinRespuesta), isTrue);
      expect(SolicitudEstado.isTerminal(SolicitudEstado.buscando), isFalse);
      expect(SolicitudEstado.isTerminal(SolicitudEstado.asignado), isFalse);
    });

    test('ningún estado es simultáneamente activo y terminal', () {
      const todos = [
        SolicitudEstado.buscando,
        SolicitudEstado.asignado,
        SolicitudEstado.enEspera,
        SolicitudEstado.enCamino,
        SolicitudEstado.enRuta,
        SolicitudEstado.completado,
        SolicitudEstado.cancelado,
        SolicitudEstado.sinRespuesta,
      ];
      for (final estado in todos) {
        final activo = SolicitudEstado.isSesionActiva(estado);
        final terminal = SolicitudEstado.isTerminal(estado);
        expect(
          activo && terminal,
          isFalse,
          reason: '$estado no puede ser activo y terminal a la vez',
        );
      }
    });
  });
}
