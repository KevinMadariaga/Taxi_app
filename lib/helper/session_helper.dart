import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class SessionHelper {
  SessionHelper._();

  static const String _keyIsLogged = 'is_logged_in';
  static const String _keyRole = 'user_role';
  static const String _keyUid = 'user_uid';
  static const String _keyCachedName = 'cached_user_name';
  static const String _keyActiveSolicitud = 'active_solicitud_id';
  static const String _keyActiveSolicitudScreen = 'active_solicitud_screen';

  static Future<void> saveSession(String role, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLogged, true);
      await prefs.setString(_keyRole, role);
      await prefs.setString(_keyUid, uid);
    } catch (_) {}
  }

  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_keyUid);

      // Delete local profile/vehicle files cached per user.
      if (uid != null && uid.isNotEmpty) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final profileJpg = File('${dir.path}/profile_$uid.jpg');
          final profileWebp = File('${dir.path}/profile_$uid.webp');
          final vehicleJpg = File('${dir.path}/vehicle_$uid.jpg');
          final vehicleWebp = File('${dir.path}/vehicle_$uid.webp');

          for (final f in [profileJpg, profileWebp, vehicleJpg, vehicleWebp]) {
            if (f.existsSync()) {
              await f.delete();
            }
          }
        } catch (_) {}
      }

      await prefs.remove(_keyIsLogged);
      await prefs.remove(_keyRole);
      await prefs.remove(_keyUid);
      await prefs.remove(_keyCachedName);
      await prefs.remove(_keyActiveSolicitud);
      await prefs.remove('conductor_solicitud_activa');
      await prefs.remove('cliente_solicitud_activa');

      final keys = prefs.getKeys().toList(growable: false);
      for (final key in keys) {
        if (key.startsWith('route_cache_') ||
            key.startsWith('trip_cache_') ||
            key.startsWith('solicitud_progreso_')) {
          await prefs.remove(key);
        }
      }

      try {
        _cachedNameController.add(null);
      } catch (_) {}
      try {
        _activeSolicitudController.add(null);
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> saveCachedName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCachedName, name);
      try {
        _cachedNameController.add(name);
      } catch (_) {}
    } catch (_) {}
  }

  // Stream controller to notify listeners when cached name changes
  static final StreamController<String?> _cachedNameController =
      StreamController<String?>.broadcast();

  static Stream<String?> get cachedNameStream => _cachedNameController.stream;

  static Future<String?> getCachedName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyCachedName);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCachedName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCachedName);
      try {
        _cachedNameController.add(null);
      } catch (_) {}
    } catch (_) {}
  }

  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyIsLogged) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRole);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getUserUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyUid);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActiveSolicitud(String solicitudId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActiveSolicitud, solicitudId);
      try {
        _activeSolicitudController.add(solicitudId);
      } catch (_) {}
    } catch (_) {}
  }

  static final StreamController<String?> _activeSolicitudController =
      StreamController<String?>.broadcast();

  static Stream<String?> get activeSolicitudStream =>
      _activeSolicitudController.stream;

  static Future<String?> getActiveSolicitud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyActiveSolicitud);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActiveSolicitud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveSolicitud);
      try {
        _activeSolicitudController.add(null);
      } catch (_) {}
    } catch (_) {}
  }

  // Persist the last active pantalla for a solicitud so the app can restore
  // the exact screen after a restart/hot-reload.
  static Future<void> setActiveSolicitudScreen(String screenId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyActiveSolicitudScreen, screenId);
    } catch (_) {}
  }

  static Future<String?> getActiveSolicitudScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyActiveSolicitudScreen);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActiveSolicitudScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveSolicitudScreen);
    } catch (_) {}
  }

  // Backwards-compatible thin wrappers: keep original names but notify as well
  static Future<void> setActiveSolicitudNotify(String solicitudId) async {
    await setActiveSolicitud(solicitudId);
    _activeSolicitudController.add(solicitudId);
  }

  static Future<void> clearActiveSolicitudNotify() async {
    await clearActiveSolicitud();
    _activeSolicitudController.add(null);
  }

  // Emit change events when setting/clearing active solicitud
  static Future<void> setActiveSolicitudAndNotify(String solicitudId) async {
    try {
      await setActiveSolicitud(solicitudId);
      _activeSolicitudController.add(solicitudId);
    } catch (_) {}
  }

  static Future<void> clearActiveSolicitudAndNotify() async {
    try {
      await clearActiveSolicitud();
      _activeSolicitudController.add(null);
    } catch (_) {}
  }
}
