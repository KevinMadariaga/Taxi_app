import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Fuente de datos para autenticación y limpieza de sesión usando Firebase.
class FirebaseDataSource {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Inicia sesión con email y contraseña usando Firebase Auth.
  /// Devuelve el uid del usuario recién autenticado.
  Future<String> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user?.uid ?? _auth.currentUser?.uid ?? '';
  }

  /// Cierra sesión y limpia datos locales y de sesión.
  ///
  /// ⚠️ Camino legacy, hoy sin llamadores reales (solo lo alcanza
  /// `AuthViewModel.logout()`, que tampoco tiene llamadores). El cierre de
  /// sesión productivo de las tres pantallas es `AuthService.logout()`, que
  /// además desvincula el token FCM, corta el tracking en segundo plano y
  /// limpia la bandeja de notificaciones. Si se vuelve a cablear esto, usar
  /// `AuthService.logout()` en su lugar o replicar esos tres pasos.
  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'firebaseDB');
    }
    await _clearLocalSessionAndCache();
  }

  /// Limpia la sesión local, solicitudes activas y cachés de rutas.
  Future<void> _clearLocalSessionAndCache() async {
    // Limpiar sesión guardada
    try {
      await SessionHelper.clearSession();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'firebaseDB');
    }
    // Limpiar solicitud activa
    try {
      await SessionHelper.clearActiveSolicitud();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'firebaseDB');
    }
    // Limpiar caché de rutas y claves legacy
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith('route_cache_') ||
            k.startsWith('trip_cache_') ||
            k == 'conductor_solicitud_activa' ||
            k == 'cliente_solicitud_activa' ||
            k == 'active_solicitud_id' ||
            k.startsWith('solicitud_progreso_')) {
          await prefs.remove(k);
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'firebaseDB');
    }
  }
}
