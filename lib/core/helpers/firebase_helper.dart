import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/firebase_options.dart';

class FirebaseHelper {
  /// App Check solo en builds que no son debug y fuera de web.
  @visibleForTesting
  static bool debeActivarAppCheck({
    required bool esDebug,
    required bool esWeb,
  }) => !esDebug && !esWeb;

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

      // App Check en release para ambas plataformas: Play Integrity en
      // Android (proveedor ya registrado en Firebase para la app Android) y
      // App Attest en iOS. Hoy los servicios están en UNENFORCED (modo
      // monitor): las peticiones sin token válido pasan igual, así que esto
      // no puede dejar sin FCM a nadie; primero se miden las métricas y solo
      // después se hace enforcement. Requisito para que los tokens de Android
      // sean válidos: la SHA-256 de la llave de firma de Play (Play App
      // Signing) registrada en la app Android de Firebase.
      // En debug se omite (el token de depuración habría que registrarlo a
      // mano en la consola).
      if (FirebaseHelper.debeActivarAppCheck(
        esDebug: kDebugMode,
        esWeb: kIsWeb,
      )) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
          providerApple: const AppleAppAttestProvider(),
        );
      }

      // Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      debugPrint('Firebase, Crashlytics y App Check iniciados correctamente');
    } catch (e) {
      debugPrint('Error initializing Firebase/Crashlytics: $e');
      // Se conserva la causa original: `main()` la muestra en la pantalla de
      // error de arranque, y un `Exception` genérico dejaba sin diagnóstico
      // (no se sabía si fue red, config corrupta o App Check).
      Error.throwWithStackTrace(
        Exception('Error initializing Firebase/Crashlytics: $e'),
        StackTrace.current,
      );
    }
  }
}
