import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Reporta a Crashlytics excepciones que un catch necesita tragar para no
/// interrumpir el flujo (ej. una carga best-effort), pero que no deben
/// quedar invisibles en producción como pasaba con los catches vacíos que
/// reemplaza.
class ErrorReporter {
  ErrorReporter._();

  static void report(Object error, StackTrace stackTrace, {String? reason}) {
    if (kDebugMode) {
      debugPrint('[ErrorReporter]${reason != null ? ' $reason:' : ''} $error');
    }
    // `recordError` es async; sin `await` acá (este método es sync/best-effort
    // a propósito), una excepción dentro de esa función async nunca llega a
    // un try/catch síncrono alrededor de la llamada — Dart solo la entrega
    // como rechazo del Future devuelto. `catchError` es la única forma real
    // de evitar que Crashlytics no listo (init temprano de la app, o entorno
    // de test sin el plugin mockeado) rompa el flujo que este reporter existe
    // para proteger.
    FirebaseCrashlytics.instance
        .recordError(error, stackTrace, reason: reason, fatal: false)
        .catchError((_) {});
  }
}
