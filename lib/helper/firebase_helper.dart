import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/firebase_options.dart';

class FirebaseHelper {
  /// Inicializa Firebase. Lanzará una excepción si falla.
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint("Firebase Iniciado correctamente");
    } catch (e) {
      debugPrint("Error initializing Firebase: $e");
      throw Exception("Error initializing Firebase");
    }
  }
}
