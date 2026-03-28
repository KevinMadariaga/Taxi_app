import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/firebase_options.dart';

class FirebaseHelper {
  /// Inicializa Firebase, Crashlytics y App Check.
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // App Check: solo activar en producción con AppAttest.
      // En modo debug, omitir App Check para no bloquear FCM con errores 403
      // (el token debug debe registrarse primero en Firebase Console).
      // Para habilitar en producción, configura App Attest en Apple Developer Portal
      // y activa App Check en la consola de Firebase.
      if (!kDebugMode) {
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
