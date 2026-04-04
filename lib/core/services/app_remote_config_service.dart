import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class AppRemoteConfigService {
  AppRemoteConfigService._();

  static final AppRemoteConfigService instance = AppRemoteConfigService._();

  static const String minimumRequiredVersionKey = 'minimum_required_version';

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  bool _configured = false;

  Future<String?> fetchMinimumRequiredVersion() async {
    try {
      if (!_configured) {
        await _remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 10),
            minimumFetchInterval: kDebugMode
                ? const Duration(minutes: 1)
                : const Duration(hours: 6),
          ),
        );

        await _remoteConfig.setDefaults(const {minimumRequiredVersionKey: ''});

        _configured = true;
      }

      await _remoteConfig.fetchAndActivate();
      final value = _remoteConfig.getString(minimumRequiredVersionKey).trim();
      return value.isEmpty ? null : value;
    } catch (error) {
      debugPrint('[RemoteConfig] Error obteniendo versión mínima: $error');
      return null;
    }
  }
}
