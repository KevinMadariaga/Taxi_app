import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/firebase_options.dart';

class FirebaseHelper {
  /// Inicializa Firebase y Crashlytics. Lanzará una excepción si falla.
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Activar Firebase App Check para proteger llamadas a Firebase (Play Integrity en Android).
      try {
        if (!kIsWeb) {
          await FirebaseAppCheck.instance.activate(
            androidProvider: AndroidProvider.playIntegrity,
            appleProvider: AppleProvider.deviceCheck,
          );
          debugPrint('Firebase App Check activado');
        }
      } catch (e) {
        debugPrint('Error activando Firebase App Check: $e');
      }
      // Inicializa Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      debugPrint("Firebase y Crashlytics iniciados correctamente");
    } catch (e) {
      debugPrint("Error initializing Firebase/Crashlytics: $e");
      throw Exception("Error initializing Firebase/Crashlytics");
    }
  }
}
