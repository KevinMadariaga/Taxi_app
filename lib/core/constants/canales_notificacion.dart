import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// Canal de notificación con sonido propio de Ride.
///
/// La mitad Dart de un contrato con `functions/notificaciones.js`
/// (`CANALES` y `canalPara`): los dos lados deben elegir el mismo canal para
/// el mismo evento. Lo fija `test/canales_notificacion_test.dart`.
///
/// **Un canal de Android no se puede modificar una vez creado en el
/// teléfono**: cambiarle el sonido o la importancia exige un id nuevo
/// (`_v2`), y borrar el viejo con `deleteNotificationChannel`.
class CanalNotificacion {
  const CanalNotificacion({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.importancia,
    this.sonido,
    this.insistente = false,
  });

  final String id;

  /// Nombre y descripción: el usuario los ve en los ajustes del teléfono.
  final String nombre;
  final String descripcion;
  final Importance importancia;

  /// Nombre base del audio: `res/raw/<sonido>.mp3` en Android y
  /// `<sonido>.caf` en el bundle de iOS. `null`: el sonido del sistema.
  final String? sonido;

  /// Android repite el sonido hasta que la tocan, la descartan o la app la
  /// cancela (la solicitud dejó de estar disponible).
  final bool insistente;

  String? get sonidoIos => sonido == null ? null : '$sonido.caf';
}

abstract final class CanalesNotificacion {
  static const solicitudes = CanalNotificacion(
    id: 'solicitudes_conductor_v1',
    nombre: 'Solicitudes de viaje',
    descripcion: 'Suena cuando un pasajero cerca pide un viaje.',
    importancia: Importance.max,
    sonido: 'nueva_solicitud',
    insistente: true,
  );

  static const estadoViaje = CanalNotificacion(
    id: 'estado_viaje_v1',
    nombre: 'Estado del viaje',
    descripcion:
        'Conductor asignado, en camino, llegada, inicio y fin del viaje, '
        'contraofertas.',
    importancia: Importance.high,
    sonido: 'estado_viaje',
  );

  static const cancelado = CanalNotificacion(
    id: 'viaje_cancelado_v1',
    nombre: 'Viajes cancelados',
    descripcion: 'Cuando un viaje se cancela o se queda sin respuesta.',
    importancia: Importance.high,
    sonido: 'viaje_cancelado',
  );

  static const mensajes = CanalNotificacion(
    id: 'mensajes_v1',
    nombre: 'Mensajes',
    descripcion: 'Chat del viaje y soporte.',
    importancia: Importance.max,
    sonido: 'mensaje',
  );

  /// Sin ventana emergente: se puede silenciar sin silenciar las
  /// solicitudes. `_v2`: la `_v1` se creó con el sonido del sistema.
  static const promociones = CanalNotificacion(
    id: 'promociones_v2',
    nombre: 'Promociones y novedades',
    descripcion: 'Ofertas y novedades de Ride.',
    importancia: Importance.defaultImportance,
    sonido: 'mensaje',
  );

  /// Todo lo demás: membresía, método de pago, avisos de la app, admin.
  static const avisos = CanalNotificacion(
    id: 'avisos_v1',
    nombre: 'Avisos de Ride',
    descripcion: 'Membresía, pagos y otros avisos de la app.',
    importancia: Importance.high,
    sonido: 'mensaje',
  );

  static const todos = [
    solicitudes,
    estadoViaje,
    cancelado,
    mensajes,
    promociones,
    avisos,
  ];

  /// Canales que existieron y hay que borrar del teléfono.
  static const retirados = ['promociones_v1'];

  /// Lo que no lleva sonido de la familia: las emergencias conservan su
  /// alarma, distinta de todo lo cotidiano.
  static const tiposSinFamilia = {'emergencia'};

  static CanalNotificacion? porId(String? id) {
    for (final c in todos) {
      if (c.id == id) return c;
    }
    return null;
  }

  static const _estadosCancelados = {
    SolicitudEstado.cancelado,
    SolicitudEstado.sinRespuesta,
  };

  /// Buenas noticias del viaje, para cualquiera de los dos roles. `buscando`
  /// llega cuando se activa un viaje programado.
  static const _estadosDelViaje = {
    SolicitudEstado.buscando,
    SolicitudEstado.asignado,
    SolicitudEstado.enEspera,
    SolicitudEstado.enCamino,
    SolicitudEstado.enRuta,
    SolicitudEstado.completado,
  };

  /// `null` solo para [tiposSinFamilia]: todo lo demás suena a Ride.
  static CanalNotificacion? para(String tipo, {String? estado}) {
    if (tiposSinFamilia.contains(tipo)) return null;
    switch (tipo) {
      case 'nueva_solicitud':
        return solicitudes;
      case 'conductor_cerca':
      case 'contraoferta':
        return estadoViaje;
      case 'trip_status_change':
        if (_estadosDelViaje.contains(estado)) return estadoViaje;
        if (_estadosCancelados.contains(estado)) return cancelado;
        return avisos;
      case 'trip_chat_message':
      case 'soporte_chat':
      case 'soporte_chat_respuesta':
        return mensajes;
      case 'promo':
        return promociones;
    }
    return avisos;
  }
}
