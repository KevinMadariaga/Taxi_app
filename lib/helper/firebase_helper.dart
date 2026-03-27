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
      // App Check desactivado para evitar bloqueos innecesarios en desarrollo y producción.
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
