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

  /// Key de Google Static Maps API (mapa estático de los home de cliente y
  /// conductor). Vive acá y no en `--dart-define` para que funcione sin
  /// importar cómo se corra/compile la app (terminal, botón visual, CI) —
  /// un dart-define exige recordar pasar el flag siempre, esto no.
  /// Configúrala en Firebase Remote Config console con nombre
  /// `static_maps_api_key`.
  static const String staticMapsApiKeyKey = 'static_maps_api_key';

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  bool _configured = false;

  // Memoiza el Future para que los widgets del mapa (que pueden reconstruirse
  // seguido) no disparen un fetch nuevo cada vez — se resuelve una sola vez
  // por sesión de la app.
  Future<String>? _staticMapsKeyFuture;

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
      staticMapsApiKeyKey: '',
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

  /// Devuelve '' (nunca null) si no se pudo resolver, para que los widgets
  /// del mapa solo necesiten chequear `.isEmpty`.
  Future<String> fetchStaticMapsApiKey() {
    return _staticMapsKeyFuture ??= _fetchString(
      staticMapsApiKeyKey,
    ).then((value) => value ?? '');
  }

  /// Limpia el Future memoizado de la key de Static Maps. Sin red,
  /// `fetchStaticMapsApiKey()` cae a `''` y ese resultado queda pegado toda
  /// la sesión (ver comentario en `_staticMapsKeyFuture`) — `ConectividadGate`
  /// llama esto al detectar que la conexión volvió, para que el próximo
  /// build del mapa pida la key de nuevo en vez de seguir mostrando el
  /// placeholder hasta que el usuario reinicie la app.
  void invalidateStaticMapsKeyCache() {
    _staticMapsKeyFuture = null;
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
