import 'package:connectivity_plus/connectivity_plus.dart';

/// Chequeo proactivo de conectividad, distinto de `esErrorDeConexion`
/// (`network_error_helper.dart`), que solo clasifica una excepción YA
/// ocurrida. Este servicio permite saber ANTES de que algo falle si hay red,
/// para avisar al usuario en vez de dejarlo ver pantallas rotas en silencio
/// (ver `ConectividadGate`).
class ConectividadService {
  /// [connectivity] es inyectable solo para tests (fake); en la app real se
  /// usa siempre `ConectividadService.instance`.
  ConectividadService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  static final ConectividadService instance = ConectividadService();

  final Connectivity _connectivity;

  bool _sinNinguna(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
  }

  /// Chequeo puntual. `true` si hay alguna interfaz de red activa (wifi,
  /// datos móviles, ethernet…) — no confirma que haya salida real a
  /// internet (una wifi con portal cautivo también cuenta como conectada),
  /// pero cubre el caso reportado: modo avión / sin señal / sin wifi.
  Future<bool> hayConexion() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return !_sinNinguna(results);
    } catch (_) {
      // Si el plugin falla, no bloquear al usuario con un falso "sin red".
      return true;
    }
  }

  /// Emite `true`/`false` cada vez que cambia la conectividad del sistema.
  Stream<bool> get onConectividadCambia {
    return _connectivity.onConnectivityChanged.map(
      (results) => !_sinNinguna(results),
    );
  }
}
