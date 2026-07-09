import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/firebase_options.dart';
import 'dart:io' show Platform;

class FirebaseHelper {
  /// Inicializa Firebase, Crashlytics y App Check.
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Persistencia offline: las escrituras (ej. ubicación del conductor) hechas
      // sin conexión quedan en la cola local y se suben solas al reconectar (y se
      // limpian de la cola). Default en móvil; lo dejamos explícito.
      if (!kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }

      // App Check: solo activar en producción con AppAttest (iOS).
      // En Android NO se activa: activate() trae androidProvider con default
      // AndroidProvider.playIntegrity, y Play Integrity no está configurado
      // (huella SHA-256 release en Play Console/Firebase). Con enforcement
      // activo en Firestore/Cloud Functions, las peticiones sin token válido
      // se rechazan con 403 en silencio → fcmToken nunca se persiste → no
      // llegan notificaciones FCM en Android. iOS sí funciona porque AppAttest
      // está bien configurado.
      // En modo debug, omitir App Check para no bloquear FCM con errores 403
      // (el token debug debe registrarse primero en Firebase Console).
      if (!kDebugMode && !kIsWeb && Platform.isIOS) {
        await FirebaseAppCheck.instance.activate(
          providerApple: const AppleAppAttestProvider(),
        );
      }

      // Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      debugPrint('Firebase, Crashlytics y App Check iniciados correctamente');
    } catch (e) {
      debugPrint('Error initializing Firebase/Crashlytics: $e');
      throw Exception('Error initializing Firebase/Crashlytics');
    }
  }
}
