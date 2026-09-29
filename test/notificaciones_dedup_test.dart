import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/services/registro_avisos.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AvisoPush', () {
    test('local y push del mismo evento tienen la misma claveEvento', () {
      final local = AvisoPush('trip_status_change', 'sol1', estado: 'asignado');
      final push = AvisoPush.desdeDatos({
        'type': 'trip_status_change',
        'notifClave': claveNotificacion('trip_status_change', 'sol1'),
        'solicitudId': 'sol1',
        'estado': 'asignado',
      });
      expect(push.claveEvento, local.claveEvento);
      expect(push.esEventoUnico, isTrue);
    });

    test('cada estado del viaje es un evento distinto', () {
      expect(
        AvisoPush('trip_status_change', 's', estado: 'asignado').claveEvento,
        isNot(
          AvisoPush('trip_status_change', 's', estado: 'en ruta').claveEvento,
        ),
      );
    });

    test('chat y contraoferta se repiten: no son evento único', () {
      expect(AvisoPush('trip_chat_message', 's').esEventoUnico, isFalse);
      expect(AvisoPush('contraoferta', 's').esEventoUnico, isFalse);
    });
  });

  group('RegistroAvisos', () {
    test('el primero reclama; el segundo se descarta', () async {
      expect(await RegistroAvisos.reclamar('e1'), isTrue);
      expect(await RegistroAvisos.reclamar('e1'), isFalse);
      expect(await RegistroAvisos.reclamar('e2'), isTrue);
    });

    test('pasada la ventana se puede volver a avisar', () async {
      final t0 = DateTime(2026, 9, 29, 12);
      expect(await RegistroAvisos.reclamar('e', ahora: t0), isTrue);
      expect(
        await RegistroAvisos.reclamar(
          'e',
          ahora: t0.add(RegistroAvisos.ventana + const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });

  group('NotificacionesServicio.debeMostrar', () {
    final asignado = AvisoPush('trip_status_change', 's', estado: 'asignado');

    test(
      'aviso local en background: lo cubre el push, no se muestra',
      () async {
        expect(
          await NotificacionesServicio.debeMostrar(
            asignado,
            desdePush: false,
            enPrimerPlano: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'si llega primero el push, el local del mismo evento no sale',
      () async {
        expect(
          await NotificacionesServicio.debeMostrar(
            asignado,
            desdePush: true,
            enPrimerPlano: false,
          ),
          isTrue,
        );
        expect(
          await NotificacionesServicio.debeMostrar(
            asignado,
            desdePush: false,
            enPrimerPlano: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'si llega primero el local, el push del mismo evento no sale',
      () async {
        expect(
          await NotificacionesServicio.debeMostrar(
            asignado,
            desdePush: false,
            enPrimerPlano: true,
          ),
          isTrue,
        );
        expect(
          await NotificacionesServicio.debeMostrar(
            asignado,
            desdePush: true,
            enPrimerPlano: true,
          ),
          isFalse,
        );
      },
    );

    test('sin push gemelo se muestra siempre', () async {
      expect(
        await NotificacionesServicio.debeMostrar(
          null,
          desdePush: false,
          enPrimerPlano: false,
        ),
        isTrue,
      );
    });

    test('mensajes de chat seguidos avisan todos en primer plano', () async {
      final chat = AvisoPush('trip_chat_message', 's');
      for (var i = 0; i < 2; i++) {
        expect(
          await NotificacionesServicio.debeMostrar(
            chat,
            desdePush: false,
            enPrimerPlano: true,
          ),
          isTrue,
        );
      }
    });
  });
}
