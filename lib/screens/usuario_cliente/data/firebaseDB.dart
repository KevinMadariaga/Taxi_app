import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/helper/session_helper.dart';

class FirebaseDataSource {
  final _auth = FirebaseAuth.instance;

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> logout() async {
    await _auth.signOut();

    // Ensure local session and cached route data are removed to avoid leaking
    // previous user's data into the next login.
    try {
      await SessionHelper.clearSession();
    } catch (_) {}
    try {
      await SessionHelper.clearActiveSolicitud();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      // Remove route cache keys and legacy active-solicitud keys
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith('route_cache_') || k == 'conductor_solicitud_activa' || k == 'cliente_solicitud_activa' || k.startsWith('solicitud_progreso_')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }
}
