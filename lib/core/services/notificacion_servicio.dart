import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui' show Color;

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

  // IDs de notificaciones por tipo
  static const int _chatNotificationId = 1;
  static const int _tripNotificationId = 2;
  static const int _systemNotificationId = 3;

  // Canales de notificación
  static const String _chatChannelId = 'taxi_chat_channel';
  static const String _chatChannelName = 'Mensajes de Chat';

  static const String _tripChannelId = 'taxi_trip_channel';
  static const String _tripChannelName = 'Notificaciones de Viaje';

  static const String _systemChannelId = 'taxi_system_channel';
  static const String _systemChannelName = 'Notificaciones del Sistema';

  static const String _adminChannelId = 'taxi_admin_channel';
  static const String _adminChannelName = 'Notificaciones del Administrador';

  static const String _emergenciaChannelId = 'taxi_emergencia_channel';
  static const String _emergenciaChannelName = 'Emergencias';

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
            AndroidFlutterLocalNotificationsPlugin>();

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

    _initialized = true;
  }

  /// Notificación simple (genérica) con ID opcional
  Future<void> showNotification({
    int? id,
    required String title,
    required String body,
    String? channelId,
    String? channelName,
    String? payload,
  }) async {
    await _ensureInitialized();

    final androidDetails = AndroidNotificationDetails(
      channelId ?? _systemChannelId,
      channelName ?? _systemChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'sistema',
      interruptionLevel: InterruptionLevel.active,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id ?? _systemNotificationId,
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
  }) async {
    await _ensureInitialized();

    final androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      _chatChannelName,
      channelDescription: 'Notificaciones de mensajes de chat',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: 'chat',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _chatNotificationId,
      senderName,
      message,
      notificationDetails,
    );
  }

  /// Notificación relacionada con viajes (asignación, inicio, finalización, etc.)
  Future<void> showTripNotification({
    required String title,
    required String body,
    bool playSound = true,
    bool vibrate = true,
  }) async {
    await _ensureInitialized();

    final androidDetails = AndroidNotificationDetails(
      _tripChannelId,
      _tripChannelName,
      channelDescription: 'Notificaciones relacionadas con viajes',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: vibrate,
      playSound: playSound,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_color'),
      color: const Color(0xFF081B33),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      threadIdentifier: 'viaje',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(_tripNotificationId, title, body, notificationDetails);
  }

  /// Notificación de cancelación de solicitud
  Future<void> showCancellationNotification({
    required String title,
    required String body,
  }) async {
    await showTripNotification(
      title: title,
      body: body,
      playSound: true,
      vibrate: true,
    );
  }

  /// Notificación de asignación de conductor/cliente
  Future<void> showAssignmentNotification({
    required String title,
    required String body,
  }) async {
    await showTripNotification(
      title: title,
      body: body,
      playSound: true,
      vibrate: true,
    );
  }

  /// Cancela todas las notificaciones activas
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancela una notificación específica por ID
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// Asegura que el servicio esté inicializado antes de usarlo
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }
}
