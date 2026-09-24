import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/controllers/pending_solicitudes_controller.dart';

/// Las dos piezas que hacen que el aviso "Solicitud entrante" se pueda
/// RETIRAR de la bandeja del conductor:
///
/// 1. que el id con el que se muestra sea el mismo con el que se cancela
///    (`idNotificacionDeMensaje`), y
/// 2. que al abrir la app se limpie lo que ya no está en la lista, para el
///    caso en que el push silencioso de retirada no llegó — Android no
///    entrega data-only si el conductor forzó el cierre.
void main() {
  group('idNotificacionDeMensaje', () {
    test('usa el notifId que manda el backend', () {
      final id = idNotificacionDeMensaje({
        'notifId': '12345',
        'notifClave': 'nueva_solicitud_cliX',
        'type': 'nueva_solicitud',
        'solicitudId': 'sol1',
      });
      expect(id, 12345);
    });

    test('cae a la clave si no vino el id', () {
      final id = idNotificacionDeMensaje({
        'notifClave': 'nueva_solicitud_cliX',
        'type': 'nueva_solicitud',
        'solicitudId': 'sol1',
      });
      expect(id, idNotificacion('nueva_solicitud_cliX'));
    });

    test('cae a tipo+solicitud si tampoco vino la clave', () {
      final id = idNotificacionDeMensaje({
        'type': 'trip_status_change',
        'solicitudId': 'sol1',
      });
      expect(id, idNotificacionDe('trip_status_change', 'sol1'));
    });

    test('con un push sin nada reconocible cae al id del canal de viajes', () {
      expect(
        idNotificacionDeMensaje({'type': 'algo_raro'}),
        NotificacionesServicio.tripNotificationId,
      );
      expect(
        idNotificacionDeMensaje(const {}),
        NotificacionesServicio.tripNotificationId,
      );
    });

    test('el retiro borra la notificación que mostró el otro push', () {
      // Es el invariante del que depende todo: si divergen, la notificación
      // se muestra y nunca se puede borrar. El backend manda el `notifId` en
      // el push que la MUESTRA y recompone el retiro desde la clave que dejó
      // guardada, así que lo que hay que fijar es que la clave sola alcance
      // para reconstruir el mismo id.
      const clienteId = 'cliX';
      final clave = claveNotificacion('nueva_solicitud', clienteId);

      final mostrado = idNotificacionDeMensaje({
        'notifId': '${idNotificacion(clave)}',
        'notifClave': clave,
        'type': 'nueva_solicitud',
        'clienteId': clienteId,
      });
      // El retiro NO reenvía el id original: lo deriva de la clave.
      final retirado = idNotificacionDeMensaje({
        'notifClave': clave,
        'type': 'retirar_notificacion',
      });
      expect(retirado, mostrado);

      // Y la red de seguridad local, que no ve ningún push, llega al mismo id
      // partiendo solo del clienteId que trae la solicitud.
      expect(idNotificacionDe('nueva_solicitud', clienteId), mostrado);
    });

    test('el retiro de OTRO cliente no borra este aviso', () {
      final deA = idNotificacionDe('nueva_solicitud', 'cliA');
      final deB = idNotificacionDeMensaje({
        'notifClave': claveNotificacion('nueva_solicitud', 'cliB'),
        'type': 'retirar_notificacion',
      });
      expect(deA, isNot(deB));
    });
  });

  group('clientesSinSolicitudVigente', () {
    Set<String> calcular({
      required Set<String> previas,
      required Set<String> vigentes,
      required Map<String, String> mapa,
    }) => PendingSolicitudesController.clientesSinSolicitudVigente(
      previas: previas,
      vigentes: vigentes,
      clientePorSolicitud: mapa,
    );

    test('devuelve el cliente de la solicitud que desapareció', () {
      expect(
        calcular(
          previas: {'sol1', 'sol2'},
          vigentes: {'sol2'},
          mapa: {'sol1': 'cliA', 'sol2': 'cliB'},
        ),
        {'cliA'},
      );
    });

    test('no devuelve nada si no desapareció ninguna', () {
      expect(
        calcular(
          previas: {'sol1'},
          vigentes: {'sol1', 'sol2'},
          mapa: {'sol1': 'cliA', 'sol2': 'cliB'},
        ),
        isEmpty,
      );
    });

    test('NO cancela si el mismo cliente dejó otra solicitud viva', () {
      // La clave del aviso es el cliente: cancelarla acá le borraría al
      // conductor la notificación de `sol2`, que sigue disponible.
      expect(
        calcular(
          previas: {'sol1', 'sol2'},
          vigentes: {'sol2'},
          mapa: {'sol1': 'cliA', 'sol2': 'cliA'},
        ),
        isEmpty,
      );
    });

    test('ignora solicitudes sin cliente conocido', () {
      expect(
        calcular(
          previas: {'sol1', 'sol2'},
          vigentes: const {},
          mapa: {'sol1': '', 'sol2': 'cliB'},
        ),
        {'cliB'},
      );
    });

    test('junta varios clientes que se fueron a la vez', () {
      expect(
        calcular(
          previas: {'sol1', 'sol2', 'sol3'},
          vigentes: {'sol3'},
          mapa: {'sol1': 'cliA', 'sol2': 'cliB', 'sol3': 'cliC'},
        ),
        {'cliA', 'cliB'},
      );
    });
  });
}
