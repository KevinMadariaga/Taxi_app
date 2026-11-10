import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:taxi_app/core/constants/canales_notificacion.dart';
import 'package:taxi_app/core/services/registro_avisos.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';

/// Servicio centralizado para notificaciones locales.
/// Implementado como singleton para compartir la misma instancia del plugin.
class NotificacionesServicio {
  // Singleton
  static NotificacionesServicio? _instance;
  static NotificacionesServicio get instance =>
      _instance ??= NotificacionesServicio._();

  /// Callback para tap en notificación. Se asigna desde main.dart.
  static void Function(String? payload)? onNotificationTap;

  // Constructor privado
  NotificacionesServicio._();

  // Plugin compartido
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // IDs de notificaciones por tipo. Públicos porque quien muestra un aviso
  // es también quien tiene que poder cancelarlo (ver `cancel`).
  static const int chatNotificationId = 1;
  static const int tripNotificationId = 2;
  static const int systemNotificationId = 3;
  static const int progresoViajeNotificationId = 4;
  static const int sonidoEstadoViajeNotificationId = 5;

  // Canales de notificación
  static const String _chatChannelId = 'taxi_chat_channel';
  static const String _chatChannelName = 'Mensajes de Chat';

  static const String _tripChannelId = 'taxi_trip_channel';
  static const String _tripChannelName = 'Notificaciones de Viaje';

  // Silencioso a propósito: se actualiza muchas veces por viaje (cada vez
  // que cambia el ETA/distancia mostrados) y no debe sonar ni vibrar en cada
  // actualización — solo la primera vez que aparece (`onlyAlertOnce`).
  static const String _progresoChannelId = 'taxi_progreso_channel';
  static const String _progresoChannelName = 'Progreso del viaje';

  static const String _systemChannelId = 'taxi_system_channel';
  static const String _systemChannelName = 'Notificaciones del Sistema';

  static const String _adminChannelId = 'taxi_admin_channel';
  static const String _adminChannelName = 'Notificaciones del Administrador';

  static const String _emergenciaChannelId = 'taxi_emergencia_channel';
  static const String _emergenciaChannelName = 'Emergencias';

  /// Lo más que suena en bucle una solicitud sin respuesta.
  static const Duration _topeInsistente = Duration(seconds: 90);

  /// Inicializa el servicio de notificaciones.
  /// Solo se inicializa una vez, llamadas subsecuentes son ignoradas.
  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: false,
    );

    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        onNotificationTap?.call(response.payload);
      },
    );

    // Confirmar permisos iOS después de la inicialización.
    // Esto garantiza que el diálogo de autorización se muestra si aún
    // no fue respondido (flutter_local_notifications lo gestiona de forma
    // correcta con UNUserNotificationCenter sin conflictos).
    final bool? iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    if (iosGranted != null) {
      debugPrint(
        iosGranted
            ? '✅ [NotificacionesServicio] Permisos iOS confirmados'
            : '⚠️ [NotificacionesServicio] Permisos iOS no concedidos',
      );
    }

    // Registrar de antemano todos los canales que un push remoto (FCM) puede
    // referenciar por android_channel_id. Si el canal no existe cuando llega
    // el push, Android lo descarta en silencio — deben existir desde el
    // arranque, no solo cuando se dispara la primera notificación local.
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _adminChannelId,
        _adminChannelName,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _tripChannelId,
        _tripChannelName,
        description: 'Notificaciones relacionadas con viajes',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description: 'Notificaciones de mensajes de chat',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _emergenciaChannelId,
        _emergenciaChannelName,
        description: 'Alertas del botón de pánico',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _progresoChannelId,
        _progresoChannelName,
        description: 'Tiempo y distancia restantes del viaje activo',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    // Era el único canal que no se declaraba acá: se materializaba implícito
    // en el primer `show`, con los valores por defecto de Android en vez de
    // los de la app.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _systemChannelId,
        _systemChannelName,
        description: 'Avisos generales de la aplicación',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    for (final id in CanalesNotificacion.retirados) {
      await androidPlugin?.deleteNotificationChannel(id);
    }
    for (final c in CanalesNotificacion.todos) {
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          c.id,
          c.nombre,
          description: c.descripcion,
          importance: c.importancia,
          playSound: true,
          sound: c.sonido == null
              ? null
              : RawResourceAndroidNotificationSound(c.sonido),
          enableVibration: true,
        ),
      );
    }

    _initialized = true;
  }

  /// Un solo aviso por evento, venga por push o sea local.
  ///
  /// - [push] es el evento del backend al que corresponde el aviso (o `null`
  ///   si ningún push lo cubre: se muestra siempre).
  /// - Aviso LOCAL con la app en segundo plano: no se muestra. El push de ese
  ///   evento ya lo dibuja el sistema, y un listener de Firestore que sigue
  ///   vivo en background (tracking del conductor) duplicaba cada aviso.
  /// - Evento único ([AvisoPush.esEventoUnico]): el primero que lo muestre lo
  ///   reclama en [RegistroAvisos] y los demás lo descartan.
  @visibleForTesting
  static Future<bool> debeMostrar(
    AvisoPush? push, {
    required bool desdePush,
    required bool enPrimerPlano,
  }) async {
    if (push == null) return true;
    if (!desdePush && !enPrimerPlano) return false;
    if (push.esEventoUnico) return RegistroAvisos.reclamar(push.claveEvento);
    return true;
  }

  Future<bool> _debeMostrar(AvisoPush? push, bool desdePush) {
    if (push == null) return Future.value(true);
    // Solo se consulta para avisos locales (isolate principal, con binding).
    final estado = desdePush ? null : WidgetsBinding.instance.lifecycleState;
    return debeMostrar(
      push,
      desdePush: desdePush,
      enPrimerPlano: estado == null || estado == AppLifecycleState.resumed,
    );
  }

  /// Notificación simple (genérica) con ID opcional
  Future<void> showNotification({
    int? id,
    required String title,
    required String body,
    String? channelId,
    String? channelName,
    String? payload,
    AvisoPush? push,
    bool desdePush = false,
    bool insistente = false,
  }) async {
    if (!await _debeMostrar(push, desdePush)) return;
    await _ensureInitialized();

    // Todo suena a Ride: el canal con sonido que pidió el llamador o el del
    // evento. Un id viejo (`taxi_*`, p.ej. de un backend anterior) no lo
    // impide; solo las emergencias conservan su canal y su alarma.
    final canal =
        CanalesNotificacion.porId(channelId) ??
        (channelId == _emergenciaChannelId
            ? null
            : push != null
            ? CanalesNotificacion.para(push.tipo, estado: push.estado)
            : CanalesNotificacion.avisos);

    final androidDetails = AndroidNotificationDetails(
      canal?.id ?? channelId ?? _systemChannelId,
      canal?.nombre ?? channelName ?? _systemChannelName,
      channelDescription: canal?.descripcion,
      importance: canal?.importancia ?? Importance.high,
      priority: Priority.high,
      sound: canal?.sonido == null
          ? null
          : RawResourceAndroidNotificationSound(canal!.sonido),
      // FLAG_INSISTENT: repite el sonido hasta que la toquen, la descarten
      // o se retire (la solicitud dejó de estar disponible). Con tope: un
      // conductor que no contesta no puede quedar sonando media hora.
      additionalFlags: insistente && (canal?.insistente ?? false)
          ? Int32List.fromList(const [4])
          : null,
      timeoutAfter: insistente && (canal?.insistente ?? false)
          ? _topeInsistente.inMilliseconds
          : null,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      sound: canal?.sonidoIos,
      threadIdentifier: 'sistema',
      interruptionLevel: canal == CanalesNotificacion.solicitudes
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id ?? systemNotificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Notificación de chat con sonido y vibración
  Future<void> showChatNotification({
    required String senderName,
    required String message,
    String? payload,
    AvisoPush? push,
  }) async {
    if (!await _debeMostrar(push, false)) return;
    await _ensureInitialized();

    const canal = CanalesNotificacion.mensajes;
    final androidDetails = AndroidNotificationDetails(
      canal.id,
      canal.nombre,
      channelDescription: canal.descripcion,
      importance: canal.importancia,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(canal.sonido),
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      sound: canal.sonidoIos,
      threadIdentifier: 'chat',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      chatNotificationId,
      senderName,
      message,
      notificationDetails,
      payload: payload,
    );
  }

  /// Notificación relacionada con viajes (asignación, inicio, finalización, etc.)
  /// [id] permite que un aviso reemplace al anterior del mismo evento en vez
  /// de apilarse; por defecto sigue siendo el id único del canal de viajes.
  Future<void> showTripNotification({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
    int? id,
    String? payload,
    AvisoPush? push,
    bool desdePush = false,
  }) async {
    if (!await _debeMostrar(push, desdePush)) return;
    await _ensureInitialized();

    // Sin evento declarado es un aviso del viaje en curso.
    final canal = push == null
        ? CanalesNotificacion.estadoViaje
        : CanalesNotificacion.para(push.tipo, estado: push.estado);

    final androidDetails = AndroidNotificationDetails(
      canal?.id ?? _tripChannelId,
      canal?.nombre ?? _tripChannelName,
      channelDescription:
          canal?.descripcion ?? 'Notificaciones relacionadas con viajes',
      importance: canal?.importancia ?? Importance.high,
      priority: Priority.high,
      enableVibration: vibrate,
      playSound: playSound,
      sound: canal?.sonido == null
          ? null
          : RawResourceAndroidNotificationSound(canal!.sonido),
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: playSound,
      sound: canal?.sonidoIos,
      threadIdentifier: 'viaje',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id ?? tripNotificationId,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Notificación persistente y silenciosa con el progreso del viaje activo
  /// (tiempo/distancia restantes), visible en la pantalla de bloqueo —
  /// `NotificacionesServicio.instance.showOrUpdateProgresoViaje` se llama
  /// muchas veces durante un mismo viaje (`ViajeClienteViewModel`, throttleado
  /// a ~10 s), siempre con el mismo ID: cada llamada REEMPLAZA la anterior en
  /// vez de apilar una nueva, y `onlyAlertOnce` evita que suene o vibre en
  /// cada actualización (solo la primera vez que aparece). `ongoing: true`
  /// para que no se pueda descartar por accidente con el viaje en curso —
  /// se cancela sola cuando el viaje termina (`ViajeClienteViewModel.dispose`
  /// ya llama a `cancelAll()`).
  ///
  /// [progreso] (0-100, opcional) dibuja la barra de progreso nativa de la
  /// notificación (Android; en iOS solo se ve el texto). Sin barra (`null`)
  /// si el viaje llama a este método antes de tener un progreso calculable.
  Future<void> showOrUpdateProgresoViaje({
    required String title,
    required String body,
    int? progreso,
  }) async {
    await _ensureInitialized();

    final androidDetails = AndroidNotificationDetails(
      _progresoChannelId,
      _progresoChannelName,
      channelDescription: 'Tiempo y distancia restantes del viaje activo',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      ongoing: true,
      showProgress: progreso != null,
      maxProgress: 100,
      progress: progreso ?? 0,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
      visibility: NotificationVisibility.public,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      threadIdentifier: 'progreso_viaje',
      interruptionLevel: InterruptionLevel.passive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      progresoViajeNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  /// El sonido de estado del viaje, para quien ya mira la pantalla del
  /// viaje: en iOS solo suena; Android no suena sin notificación, así que
  /// aparece y se retira sola a los pocos segundos.
  Future<void> sonarEstadoViaje(String title) async {
    await _ensureInitialized();
    const canal = CanalesNotificacion.estadoViaje;
    await _plugin.show(
      sonidoEstadoViajeNotificationId,
      title,
      null,
      NotificationDetails(
        android: AndroidNotificationDetails(
          canal.id,
          canal.nombre,
          channelDescription: canal.descripcion,
          importance: canal.importancia,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound(canal.sonido),
          timeoutAfter: 4000,
          icon: 'ic_notification',
          color: const Color(0xFF081B33),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBanner: false,
          presentList: false,
          presentBadge: false,
          presentSound: true,
          sound: canal.sonidoIos,
        ),
      ),
    );
  }

  /// Cancela todas las notificaciones activas
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancela una notificación específica.
  ///
  /// [tag] es imprescindible para las que dibujó el SISTEMA desde un push de
  /// FCM: esas se publican con `id 0` y el `tag` del `collapseKey`, así que un
  /// `cancel` por id no las toca. La clave viaja en `data.notifClave`.
  Future<void> cancel(int id, {String? tag}) async {
    await _ensureInitialized();
    await _plugin.cancel(id, tag: tag);
  }

  /// Asegura que el servicio esté inicializado antes de usarlo
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }
}
