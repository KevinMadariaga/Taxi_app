import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_navigator.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';

/// Handler de nivel TOP para mensajes recibidos en background/terminated.
///
/// IMPORTANTE: debe ser función de nivel superior (fuera de clase) para que
/// Firebase pueda invocarla desde un isolate separado.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] Mensaje recibido: ${message.messageId}');

  final data = message.data;
  final notification = message.notification;

  // Si el mensaje trae bloque 'notification', el OS (Android/iOS) YA la
  // muestra automáticamente en background/terminated — mostrarla también
  // aquí duplicaba el aviso (dos notificaciones para el mismo evento).
  // Solo mostramos manualmente los mensajes puramente data-only.
  if (notification != null) return;

  if (data.containsKey('title') || data.containsKey('body')) {
    final String title = data['title'] ?? 'Ride';
    final String body = data['body'] ?? 'Actualización de servicio';

    // Id determinístico por solicitud (no por messageId): si FCM reenvía el
    // mismo mensaje, el SO reemplaza la notificación en vez de apilarla.
    final solicitudId = data['solicitudId'] as String?;
    final id = (solicitudId != null && solicitudId.isNotEmpty)
        ? solicitudId.hashCode
        : message.messageId.hashCode;

    // Importante: No llamar a init() aquí si no es necesario,
    // showNotification ya lo hace con _ensureInitialized().
    await NotificacionesServicio.instance.showNotification(
      id: id,
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
    // `alert: false` a propósito: en PRIMER PLANO la notificación la muestra
    // la app, nunca el sistema.
    //
    // Con `alert: true`, iOS mostraba el banner del sistema por su cuenta —sin
    // pasar por `_onForegroundMessage`— y encima el aviso local del listener de
    // la pantalla, así que el usuario veía DOS notificaciones del mismo evento
    // (reproducido en dispositivo real con el chat del viaje). Ningún filtro en
    // el handler podía evitarlo, porque el banner del sistema no se decide en
    // Dart.
    //
    // El reparto queda: primer plano → la app (`_onForegroundMessage` o el
    // aviso del listener, exactamente uno de los dos); segundo plano o app
    // cerrada → el sistema, con el bloque `notification` de la push.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
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
      // No mostrar alertas nativas, pero seguir registrando token y handlers:
      // FCM puede seguir entregando mensajes data-only sin permiso de alerta,
      // y el usuario puede otorgar el permiso más tarde desde ajustes del SO.
      debugPrint('[FCM] Permisos de notificación denegados por el usuario');
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
    } catch (e, st) {
      debugPrint('[FCM] Error obteniendo token: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'FcmService: fallo al obtener token FCM',
      );
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
    } catch (e, st) {
      debugPrint('[FCM] Error guardando token en usuarios: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'FcmService: fallo al guardar token en usuarios/$uid',
      );
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
    } catch (e, st) {
      debugPrint('[FCM] Error guardando token en administradores: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'FcmService: fallo al guardar token en administradores/$uid',
      );
    }
  }

  /// Fuerza la actualización del token en Firestore.
  /// Llamar después de login o cambio de usuario.
  Future<void> refreshToken() async {
    await _saveCurrentToken();
  }

  /// Desvincula este dispositivo del usuario que está cerrando sesión.
  ///
  /// Llamar ANTES del `signOut()`: necesita `currentUser` para saber de qué
  /// documento borrar el token, y las reglas de Firestore exigen estar
  /// autenticado para escribirlo.
  ///
  /// Sin esto el `fcmToken` quedaba en `usuarios/{uid}` después de cerrar
  /// sesión y el dispositivo seguía recibiendo push dirigidas a esa cuenta —
  /// incluidas las del rol que se acababa de abandonar. Se borra el token del
  /// servidor y se elimina el local para que el próximo login genere uno nuevo
  /// y limpio.
  Future<void> desvincularTokenAlCerrarSesion() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid != null) {
      final firestore = FirebaseFirestore.instance;
      final borrado = {
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      };

      try {
        await firestore.collection('usuarios').doc(uid).update(borrado);
        debugPrint('[FCM] ✅ Token desvinculado de usuarios/$uid');
      } catch (e, st) {
        // `not-found` es esperado si el doc no existe; el resto sí importa.
        ErrorReporter.report(
          e,
          st,
          reason: 'FcmService: fallo al desvincular token de usuarios/$uid',
        );
      }

      try {
        final doc = await firestore.collection('administradores').doc(uid).get();
        if (doc.exists) {
          await firestore
              .collection('administradores')
              .doc(uid)
              .update({'fcmToken': FieldValue.delete()});
        }
      } catch (e, st) {
        ErrorReporter.report(
          e,
          st,
          reason: 'FcmService: fallo al desvincular token de administradores',
        );
      }
    }

    _pendingToken = null;

    // Borra el token del dispositivo: el siguiente login pide uno nuevo.
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, st) {
      ErrorReporter.report(
        e,
        st,
        reason: 'FcmService: fallo al borrar el token local',
      );
    }
  }

  // Ya no hay una lista fija de tipos con "aviso local propio". Esa lista
  // asumía que la pantalla capaz de avisar estaba siempre montada, y cuando no
  // lo estaba el aviso se perdía por completo en primer plano. Ahora la
  // decisión se toma con el estado real de la navegación — ver
  // [_pantallasDeViaje].

  /// Solicitud cuya pantalla de viaje está montada ahora mismo, si hay alguna.
  ///
  /// Lo registran `ViajeConductorScreen` / `ViajeClienteScreen` al entrar y lo
  /// limpian al salir. Sirve para decidir quién muestra el aviso en primer
  /// plano sin duplicarlo: si la pantalla del viaje está en pantalla, sus
  /// propios listeners de Firestore ya avisan en tiempo real y este handler se
  /// hace a un lado; si no lo está, el handler es el único que puede avisar.
  ///
  /// Antes esa decisión se tomaba con una lista fija de tipos
  /// (`_tiposConAvisoLocalPropio`), que asumía que la pantalla relevante SIEMPRE
  /// estaba montada. Cuando no lo estaba —cliente en el home y llega un mensaje
  /// de chat, por ejemplo— nadie mostraba nada y la notificación se perdía.
  /// Se cuenta por solicitud en vez de guardar un solo id, porque dos pantallas
  /// del MISMO viaje pueden solaparse durante una transición (p. ej.
  /// `BuscandoTaxiView` → `ViajeClienteScreen`, ambas con el mismo
  /// `solicitudId`). Con un único campo, el `dispose` de la que se va borraba el
  /// registro que la que llega acababa de poner, y el viaje quedaba marcado como
  /// "sin pantalla" aunque estuviera a la vista.
  final Map<String, int> _pantallasDeViaje = {};

  /// Chats abiertos ahora mismo. Con el chat a la vista no se notifican sus
  /// mensajes: el usuario los está leyendo.
  final Map<String, int> _chatsAbiertos = {};

  static void _registrar(Map<String, int> destino, String clave) {
    if (clave.isEmpty) return;
    destino[clave] = (destino[clave] ?? 0) + 1;
  }

  static void _liberar(Map<String, int> destino, String clave) {
    final actual = destino[clave];
    if (actual == null) return;
    if (actual <= 1) {
      destino.remove(clave);
    } else {
      destino[clave] = actual - 1;
    }
  }

  void registrarPantallaDeViaje(String solicitudId) =>
      _registrar(_pantallasDeViaje, solicitudId);

  void limpiarPantallaDeViaje(String solicitudId) =>
      _liberar(_pantallasDeViaje, solicitudId);

  void registrarChatAbierto(String solicitudId) =>
      _registrar(_chatsAbiertos, solicitudId);

  void limpiarChatAbierto(String solicitudId) =>
      _liberar(_chatsAbiertos, solicitudId);

  /// Mensajes en PRIMER PLANO.
  ///
  /// En primer plano el sistema no muestra nada por su cuenta (Android nunca lo
  /// hace, y en iOS se apagó con `alert: false` en [init]), así que la única
  /// notificación posible es la que se decida acá o la que dispare el listener
  /// de una pantalla montada. Exactamente una de las dos:
  ///
  /// - Si la pantalla del viesaje al que pertenece la push está montada, ya avisa
  ///   ella → este handler no hace nada.
  /// - Si no lo está, el handler muestra el aviso local.
  /// - Si el chat de ese viaje está abierto, sus mensajes no se notifican.
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM Foreground] ${message.notification?.title}');
    final notification = message.notification;
    final type = message.data['type'] as String? ?? '';
    final solicitudId = message.data['solicitudId'] as String? ?? '';

    // El usuario está leyendo ese chat: no notificar lo que ya ve.
    if (type == 'trip_chat_message' &&
        _chatsAbiertos.containsKey(solicitudId)) {
      return;
    }

    // La pantalla del viaje está montada: sus listeners avisan en tiempo real.
    if (_pantallasDeViaje.containsKey(solicitudId)) {
      return;
    }

    final title =
        notification?.title ?? message.data['title'] as String? ?? 'Ride';
    final body = notification?.body ?? message.data['body'] as String? ?? '';
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

  /// Vuelve al home del conductor solo si NO hay un viaje en curso.
  ///
  /// `popUntil(isFirst)` es destructivo: como la pantalla de viaje se apila
  /// con `push` sobre el home, aplicarlo durante un viaje activo expulsaría al
  /// conductor de él.
  Future<void> _irAInicioConductorSiNoHayViajeActivo(
    NavigatorState nav,
  ) async {
    try {
      final solicitudActiva = await SessionHelper.getActiveSolicitud();
      if (solicitudActiva != null && solicitudActiva.isNotEmpty) return;
    } catch (e, st) {
      // Ante la duda, NO navegar: es preferible perder el atajo a la lista
      // que arriesgarse a sacar al conductor de un viaje.
      ErrorReporter.report(e, st, reason: 'fcm_service');
      return;
    }
    if (!nav.mounted) return;
    nav.popUntil((route) => route.isFirst);
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
    //
    // PERO nunca si ya está en un viaje: la pantalla de viaje se abre con
    // `push` sobre el home, así que `popUntil(isFirst)` lo **sacaría del
    // viaje activo**. En ese caso la notificación se ignora — de todas formas
    // no puede tomar otra solicitud mientras conduce.
    if (type == 'nueva_solicitud') {
      unawaited(_irAInicioConductorSiNoHayViajeActivo(nav));
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
