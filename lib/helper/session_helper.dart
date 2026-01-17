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
      // Attempt to delete any local files cached for this user (profile image, etc.)
      try {
        final uid = prefs.getString(_keyUid);
        if (uid != null && uid.isNotEmpty) {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final profileFile = File('${dir.path}/profile_$uid.jpg');
            if (profileFile.existsSync()) {
              await profileFile.delete();
            }
            // If you have other per-user cached files following a naming pattern,
            // you can delete them here as well.
          } catch (_) {}
        }
      } catch (_) {}

      await prefs.remove(_keyIsLogged);
      await prefs.remove(_keyRole);
      await prefs.remove(_keyUid);
      try {
        await prefs.remove(_keyCachedName);
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> saveCachedName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCachedName, name);
    } catch (_) {}
  }

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
      try { _activeSolicitudController.add(solicitudId); } catch (_) {}
    } catch (_) {}
  }

  static final StreamController<String?> _activeSolicitudController = StreamController<String?>.broadcast();

  static Stream<String?> get activeSolicitudStream => _activeSolicitudController.stream;

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
      try { _activeSolicitudController.add(null); } catch (_) {}
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
