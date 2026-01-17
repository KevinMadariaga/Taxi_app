import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:taxi_app/helper/permisos_helper.dart';


/// Servicio centralizado para notificaciones locales.
/// Implementado como singleton para compartir la misma instancia del plugin.
class NotificacionesServicio {
  // Singleton
  static NotificacionesServicio? _instance;
  static NotificacionesServicio get instance => _instance ??= NotificacionesServicio._();
  
  // Constructor privado
  NotificacionesServicio._();

  // Plugin compartido
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
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

  /// Inicializa el servicio de notificaciones.
  /// Solo se inicializa una vez, llamadas subsecuentes son ignoradas.
  Future<void> init() async {
    if (_initialized) return;

    // Verificar y solicitar permisos de notificaciones
    final hasPermission = await PermissionsHelper.hasNotificationPermission();
    if (!hasPermission) {
      await PermissionsHelper.requestNotificationPermission();
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      // Optional: handle tapped notification when app is in background/terminated
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // You can handle navigation or other logic here if needed
      },
    );
    _initialized = true;
  }

  /// Notificación simple (genérica)
  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      _systemChannelId,
      _systemChannelName,
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _systemNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  /// Notificación de chat con sonido y vibración
  Future<void> showChatNotification({
    required String senderName,
    required String message,
  }) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      _chatChannelName,
      channelDescription: 'Notificaciones de mensajes de chat',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

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
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _tripNotificationId,
      title,
      body,
      notificationDetails,
    );
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
