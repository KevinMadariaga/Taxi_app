import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class AppRemoteConfigService {
  AppRemoteConfigService._([FirebaseRemoteConfig? remoteConfig])
    : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance;

  @visibleForTesting
  factory AppRemoteConfigService.paraPruebas(FirebaseRemoteConfig rc) =>
      AppRemoteConfigService._(rc);

  static final AppRemoteConfigService instance = AppRemoteConfigService._();

  static const String minimumRequiredVersionKey = 'minimum_required_version';
  static const String latestVersionKey = 'latest_version';

  /// Key de Google Static Maps API (mapa estático de los home de cliente y
  /// conductor). Vive acá y no en `--dart-define` para que funcione sin
  /// importar cómo se corra/compile la app (terminal, botón visual, CI) —
  /// un dart-define exige recordar pasar el flag siempre, esto no.
  /// Configúrala en Firebase Remote Config console con nombre
  /// `static_maps_api_key`.
  static const String staticMapsApiKeyKey = 'static_maps_api_key';

  final FirebaseRemoteConfig _remoteConfig;

  Future<void>? _configuracion;

  /// Fetch en curso, compartido. El splash, `AppUpdateGate` y los mapas piden
  /// valores casi a la vez al arrancar; cada uno lanzaba su propio
  /// `fetchAndActivate()` y en iOS el SDK cancela los que se pisan
  /// (`[firebase_remote_config/unknown] cancelled`). Si el cancelado era el de
  /// `minimum_required_version`, ese arranque se saltaba la actualización
  /// obligatoria.
  Future<void>? _fetchEnCurso;

  // Memoiza el Future para que los widgets del mapa (que pueden reconstruirse
  // seguido) no disparen un fetch nuevo cada vez — se resuelve una sola vez
  // por sesión de la app.
  Future<String>? _staticMapsKeyFuture;

  Future<void> _ensureConfigured() {
    return _configuracion ??= _configurar().catchError((Object e) {
      _configuracion = null; // reintentar en la próxima lectura
      throw e;
    });
  }

  Future<void> _configurar() async {
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
      staticMapsApiKeyKey: '',
    });
  }

  Future<void> _fetchCompartido() {
    return _fetchEnCurso ??= _remoteConfig
        .fetchAndActivate()
        .then<void>((_) {})
        .whenComplete(() => _fetchEnCurso = null);
  }

  Future<String?> fetchMinimumRequiredVersion() async {
    return _fetchString(minimumRequiredVersionKey);
  }

  Future<String?> fetchLatestVersion() async {
    return _fetchString(latestVersionKey);
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
      await _fetchCompartido();
    } catch (error) {
      // Sin red o fetch cancelado: se sigue con el último valor activado,
      // que el SDK persiste entre sesiones. Devolver null acá hacía que un
      // solo fetch fallido dejara pasar una versión por debajo de la mínima.
      debugPrint('[RemoteConfig] Fetch falló, uso el último valor: $error');
    }
    try {
      final value = _remoteConfig.getString(key).trim();
      return value.isEmpty ? null : value;
    } catch (error) {
      debugPrint('[RemoteConfig] Error obteniendo "$key": $error');
      return null;
    }
  }
}
