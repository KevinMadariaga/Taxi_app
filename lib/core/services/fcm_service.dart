import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_navigator.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';

/// Handler de nivel TOP para mensajes recibidos en background/terminated.
///
/// IMPORTANTE: debe ser función de nivel superior (fuera de clase) para que
/// Firebase pueda invocarla desde un isolate separado.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] Mensaje recibido: ${message.messageId}');

  // En Android/iOS, si el mensaje trae un bloque 'notification', el OS lo muestra.
  // Sin embargo, si es solo 'data' o queremos asegurar que sea visible:
  final data = message.data;
  final notification = message.notification;

  if (data.containsKey('title') ||
      data.containsKey('body') ||
      notification != null) {
    final String title = data['title'] ?? notification?.title ?? 'Ride';
    final String body =
        data['body'] ?? notification?.body ?? 'Actualización de servicio';

    // Importante: No llamar a init() aquí si no es necesario,
    // showNotification ya lo hace con _ensureInitialized().
    await NotificacionesServicio.instance.showNotification(
      id: message.messageId.hashCode,
      title: title,
      body: body,
    );
  }
}

/// Servicio centralizado para Firebase Cloud Messaging.
///
/// Responsabilidades:
/// 1. Solicitar permisos de notificación push en iOS
/// 2. Obtener y guardar el token FCM del usuario en Firestore
/// 3. Escuchar renovaciones del token
/// 4. Configurar handlers para mensajes en foreground, background y terminated
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  /// Token obtenido pero aún sin usuario autenticado.
  /// Se guarda en Firestore cuando authStateChanges notifique un usuario.
  String? _pendingToken;

  // ignore: unused_field — se mantiene para evitar que el GC cancele el listener
  StreamSubscription<User?>? _authStateSub;

  /// Inicializa FCM: permisos, token, handlers.
  ///
  /// Se llama en main() antes del login. Si el usuario aún no está autenticado
  /// (Firebase Auth aún no restauró la sesión), el token queda en [_pendingToken]
  /// y se persiste en Firestore tan pronto como authStateChanges detecte al usuario.
  Future<void> init() async {
    if (_initialized) return;

    // 1) Registrar handler de background antes que todo
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // iOS: mostrar notificaciones FCM también cuando la app está en primer
    // plano. badge:false — no se necesita el globo de pendientes en el
    // ícono de la app.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );

    // 2) Solicitar permisos push (en iOS muestra el diálogo nativo)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    debugPrint('[FCM] Authorization status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Permisos de notificación denegados por el usuario');
      _initialized = true;
      return;
    }

    // 3) En iOS: esperar a que el token APNs esté disponible.
    //    iOS registra el token con APNs de forma asíncrona y puede tardar
    //    varios segundos, especialmente en el primer arranque.
    if (Platform.isIOS) {
      String? apnsToken;
      const maxAttempts = 5;
      for (int i = 0; i < maxAttempts; i++) {
        apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null) {
          debugPrint('[FCM] APNs token: OK (intento ${i + 1})');
          break;
        }
        if (i < maxAttempts - 1) {
          debugPrint(
            '[FCM] APNs token no listo, reintentando en 3s... (${i + 1}/$maxAttempts)',
          );
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      if (apnsToken == null) {
        debugPrint(
          '[FCM] APNs token no disponible. '
          'FCM no funcionará hasta el próximo arranque con conexión a internet.',
        );
      }
    }

    // 4) Obtener token FCM.
    //    - Si ya hay usuario autenticado → guardar en Firestore directamente.
    //    - Si no → guardar en _pendingToken para persistirlo cuando llegue el usuario.
    await _saveCurrentToken();

    // 5) Escuchar authStateChanges para detectar cuando Firebase Auth restaura
    //    la sesión o el usuario hace login. Guarda _pendingToken si existe.
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (user == null) return;

      if (_pendingToken != null) {
        debugPrint(
          '[FCM] Usuario disponible → persistiendo token pendiente...',
        );
        await _persistToken(_pendingToken!);
        _pendingToken = null;
      } else {
        // Asegurarse de que el token más reciente esté guardado
        await _saveCurrentToken();
      }
    });

    // 6) Escuchar renovaciones del token FCM
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // 7) Handler de mensajes en primer plano (FCM no los muestra automáticamente)
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 8) Handler cuando el usuario toca una notificación (app en background)
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 9) Verificar si la app se abrió desde una notificación (app terminada)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] App abierta desde notificación: ${initialMessage.messageId}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateFromMessage(initialMessage);
      });
    }

    _initialized = true;
    debugPrint('[FCM] Servicio inicializado correctamente');
  }

  /// Obtiene el token FCM actual.
  /// Si no hay usuario autenticado, lo guarda en [_pendingToken].
  Future<void> _saveCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('[FCM] No se pudo obtener token FCM');
        return;
      }
      debugPrint('[FCM] Token obtenido: ${token.substring(0, 20)}...');

      if (FirebaseAuth.instance.currentUser == null) {
        _pendingToken = token;
        debugPrint(
          '[FCM] Sin usuario aún — token en memoria, '
          'se guardará en Firestore cuando el usuario inicie sesión.',
        );
        return;
      }

      await _persistToken(token);
    } catch (e) {
      debugPrint('[FCM] Error obteniendo token: $e');
    }
  }

  /// Callback cuando el token FCM se renueva automáticamente.
  void _onTokenRefresh(String newToken) {
    debugPrint('[FCM] Token renovado');
    _pendingToken = newToken;
    _persistToken(newToken);
  }

  /// Persiste el token en Firestore en todas las colecciones del usuario.
  Future<void> _persistToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _pendingToken = token;
      debugPrint('[FCM] Sin usuario autenticado — token en espera');
      return;
    }

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    // Guardar en `usuarios` (siempre — es la colección principal)
    try {
      await firestore.collection('usuarios').doc(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[FCM] ✅ Token guardado en usuarios/$uid');
    } catch (e) {
      debugPrint('[FCM] Error guardando token en usuarios: $e');
    }


    // Guardar en `administradores` si el documento existe (para push a admins)
    try {
      final doc = await firestore.collection('administradores').doc(uid).get();
      if (doc.exists) {
        await firestore.collection('administradores').doc(uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        debugPrint('[FCM] ✅ Token guardado en administradores/$uid');
      }
    } catch (_) {}
  }

  /// Fuerza la actualización del token en Firestore.
  /// Llamar después de login o cambio de usuario.
  Future<void> refreshToken() async {
    await _saveCurrentToken();
  }

  /// Tipos de push que ya tienen su propio aviso local en tiempo real
  /// (disparado por un listener de Firestore mientras la pantalla relevante
  /// está montada: SolicitudEstadoController, TripTrackingViewModel,
  /// InicioConductorViewModel). Este canal FCM existe para cubrir background
  /// y terminated — mostrarlo también en foreground duplicaría el aviso.
  static const _tiposConAvisoLocalPropio = {
    'trip_status_change',
    'conductor_cerca',
    'nueva_solicitud',
    'trip_chat_message',
    'soporte_chat_respuesta',
    'contraoferta',
  };

  /// Mensajes en primer plano.
  ///
  /// iOS: setForegroundNotificationPresentationOptions ya muestra el banner
  /// del sistema, así que solo usamos flutter_local_notifications para
  /// mensajes data-only (sin bloque notification). Si hay bloque notification
  /// en iOS, el OS ya lo muestra — mostrar otra local notification duplicaría.
  ///
  /// Android: FCM nunca muestra el banner en foreground por sí solo, así que
  /// siempre delegamos a flutter_local_notifications, salvo en los tipos que
  /// ya tienen su propio listener en tiempo real (ver
  /// [_tiposConAvisoLocalPropio]).
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM Foreground] ${message.notification?.title}');
    final notification = message.notification;
    final type = message.data['type'] as String? ?? '';

    if (_tiposConAvisoLocalPropio.contains(type)) {
      return;
    }

    if (Platform.isIOS && notification != null) {
      // iOS + notification block → el sistema ya lo muestra; no duplicar.
      return;
    }

    final title = notification?.title ?? message.data['title'] as String? ?? 'Ride';
    final body  = notification?.body  ?? message.data['body']  as String? ?? '';
    if (title.isEmpty && body.isEmpty) return;

    NotificacionesServicio.instance.showTripNotification(
      title: title,
      body: body,
    );
  }

  /// Cuando el usuario toca la notificación con la app en background.
  void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Notificación tocada: ${message.data}');
    _navigateFromMessage(message);
  }

  /// Navega a la pantalla correcta según el tipo de mensaje FCM.
  void _navigateFromMessage(RemoteMessage message) {
    final type = message.data['type'] as String? ?? '';
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    // Nueva solicitud de conductor → llevar al admin a su pantalla principal.
    if (type == 'solicitud_conductor') {
      nav.popUntil((route) => route.isFirst);
      return;
    }

    // Nueva solicitud cercana → llevar al conductor a su pantalla de inicio,
    // donde el listener en tiempo real ya muestra la solicitud entrante.
    if (type == 'nueva_solicitud') {
      nav.popUntil((route) => route.isFirst);
      return;
    }

    // Mensaje de chat de viaje o respuesta de soporte → la pantalla relevante
    // (tracking/chat de viaje, o chat de soporte del usuario) ya está
    // restaurada por SessionHelper/AuthService si la app estaba cerrada, o
    // sigue en el stack si solo estaba en background. No navegar aquí evita
    // abrir por error una pantalla de administrador (ver comentario en el
    // caso 'soporte_chat' más abajo, que es el sentido usuario→admin).
    if (type == 'trip_chat_message' || type == 'soporte_chat_respuesta') {
      return;
    }

    // Cambio de estado de viaje / proximidad del conductor → la pantalla de
    // seguimiento activa ya está restaurada por SessionHelper al reabrir la
    // app; si sigue en el stack (app solo en background), no hace falta
    // navegar de nuevo.
    if (type == 'trip_status_change' ||
        type == 'conductor_cerca' ||
        type == 'contraoferta') {
      return;
    }

    // Membresía activada → llevar al conductor a su pantalla de inicio.
    if (type == 'membresia_activada') {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const InicioConductor(mostrarBienvenida: true),
        ),
        (route) => false,
      );
      return;
    }

    int? tab;
    if (type == 'solicitud_activacion') tab = 0;
    if (type == 'reporte') tab = 1;
    if (type == 'soporte_chat') tab = 2;
    if (type == 'emergencia') tab = 3;

    if (tab != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => AdminHubScreen(initialTab: tab!),
        ),
      );
    }
  }
}
