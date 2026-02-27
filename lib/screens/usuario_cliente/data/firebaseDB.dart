
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/helper/session_helper.dart';

/// Fuente de datos para autenticación y limpieza de sesión usando Firebase.
class FirebaseDataSource {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Inicia sesión con email y contraseña usando Firebase Auth.
  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Cierra sesión y limpia datos locales y de sesión.
  Future<void> logout() async {
    await _auth.signOut();
    await _clearLocalSessionAndCache();
  }

  /// Limpia la sesión local, solicitudes activas y cachés de rutas.
  Future<void> _clearLocalSessionAndCache() async {
    // Limpiar sesión guardada
    try {
      await SessionHelper.clearSession();
    } catch (_) {}
    // Limpiar solicitud activa
    try {
      await SessionHelper.clearActiveSolicitud();
    } catch (_) {}
    // Limpiar caché de rutas y claves legacy
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith('route_cache_') ||
            k == 'conductor_solicitud_activa' ||
            k == 'cliente_solicitud_activa' ||
            k.startsWith('solicitud_progreso_')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }
}
