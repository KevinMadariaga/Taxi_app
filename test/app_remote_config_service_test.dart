import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/app_remote_config_service.dart';

/// Solo lo que usa `AppRemoteConfigService`; el resto cae en noSuchMethod.
class _FakeRemoteConfig implements FirebaseRemoteConfig {
  _FakeRemoteConfig(this.valores);

  final Map<String, String> valores;
  int fetches = 0;
  Completer<bool>? fetchPendiente;
  Object? errorDeFetch;

  @override
  Future<void> setConfigSettings(RemoteConfigSettings s) async {}

  @override
  Future<void> setDefaults(Map<String, dynamic> d) async {}

  @override
  Future<bool> fetchAndActivate() {
    fetches++;
    if (errorDeFetch != null) return Future.error(errorDeFetch!);
    return (fetchPendiente ??= Completer<bool>()).future;
  }

  @override
  String getString(String key) => valores[key] ?? '';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('lecturas simultáneas comparten un solo fetch', () async {
    final rc = _FakeRemoteConfig({'minimum_required_version': '1.0.9'});
    final servicio = AppRemoteConfigService.paraPruebas(rc);

    final lecturas = Future.wait([
      servicio.fetchMinimumRequiredVersion(),
      servicio.fetchLatestVersion(),
      servicio.fetchStaticMapsApiKey(),
    ]);
    await Future<void>.delayed(Duration.zero);
    rc.fetchPendiente!.complete(true);

    final r = await lecturas;
    expect(rc.fetches, 1, reason: 'antes eran 3 fetch en paralelo');
    expect(r.first, '1.0.9');
  });

  test('si el fetch falla usa el último valor activado, no null', () async {
    // El SDK persiste lo último activado: un fetch cancelado no debe dejar
    // pasar una versión por debajo de la mínima.
    final rc = _FakeRemoteConfig({'minimum_required_version': '1.0.9'})
      ..errorDeFetch = Exception('[firebase_remote_config/unknown] cancelled');
    final servicio = AppRemoteConfigService.paraPruebas(rc);

    expect(await servicio.fetchMinimumRequiredVersion(), '1.0.9');
  });

  test('sin valor guardado sigue devolviendo null', () async {
    final rc = _FakeRemoteConfig({})..errorDeFetch = Exception('sin red');
    final servicio = AppRemoteConfigService.paraPruebas(rc);

    expect(await servicio.fetchMinimumRequiredVersion(), isNull);
  });
}
