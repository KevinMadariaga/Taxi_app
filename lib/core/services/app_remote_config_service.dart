import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class AppRemoteConfigService {
  AppRemoteConfigService._();

  static final AppRemoteConfigService instance = AppRemoteConfigService._();

  static const String minimumRequiredVersionKey = 'minimum_required_version';
  static const String latestVersionKey = 'latest_version';

  /// Clave del servidor FCM (Legacy HTTP API).
  /// Configúrala en Firebase Remote Config console con nombre `fcm_server_key`.
  static const String fcmServerKeyKey = 'fcm_server_key';

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 6),
      ),
    );
    await _remoteConfig.setDefaults(const {
      minimumRequiredVersionKey: '',
      latestVersionKey: '',
      fcmServerKeyKey: '',
    });
    _configured = true;
  }

  Future<String?> fetchMinimumRequiredVersion() async {
    return _fetchString(minimumRequiredVersionKey);
  }

  Future<String?> fetchLatestVersion() async {
    return _fetchString(latestVersionKey);
  }

  Future<String?> fetchFcmServerKey() async {
    return _fetchString(fcmServerKeyKey);
  }

  Future<String?> _fetchString(String key) async {
    try {
      await _ensureConfigured();
      await _remoteConfig.fetchAndActivate();
      final value = _remoteConfig.getString(key).trim();
      return value.isEmpty ? null : value;
    } catch (error) {
      debugPrint('[RemoteConfig] Error obteniendo "$key": $error');
      return null;
    }
  }
}
