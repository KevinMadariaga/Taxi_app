// Cobertura de `ConectividadService`: chequeo proactivo de conectividad
// (distinto de `esErrorDeConexion`, que solo clasifica una excepción ya
// ocurrida). `Connectivity` de `connectivity_plus` es un singleton con
// constructor factory (siempre devuelve la misma instancia), así que para
// testear se sobreescribe `ConnectivityPlatform.instance` con un fake — es
// el punto de inyección real que expone el plugin.
import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/conectividad_service.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  List<ConnectivityResult> resultado = const [ConnectivityResult.wifi];
  final _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => resultado;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emitir(List<ConnectivityResult> r) => _controller.add(r);
}

void main() {
  late _FakeConnectivityPlatform fakePlatform;
  late ConectividadService service;

  setUp(() {
    fakePlatform = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakePlatform;
    service = ConectividadService();
  });

  group('ConectividadService.hayConexion', () {
    test('true cuando el plugin reporta wifi', () async {
      fakePlatform.resultado = const [ConnectivityResult.wifi];
      expect(await service.hayConexion(), isTrue);
    });

    test('true cuando el plugin reporta datos móviles', () async {
      fakePlatform.resultado = const [ConnectivityResult.mobile];
      expect(await service.hayConexion(), isTrue);
    });

    test('false cuando el plugin reporta none', () async {
      fakePlatform.resultado = const [ConnectivityResult.none];
      expect(await service.hayConexion(), isFalse);
    });
  });

  test(
    'onConectividadCambia mapea cada emisión del plugin a bool',
    () async {
      final expectation = expectLater(
        service.onConectividadCambia,
        emitsInOrder([false, true]),
      );
      fakePlatform.emitir(const [ConnectivityResult.none]);
      fakePlatform.emitir(const [ConnectivityResult.mobile]);
      await expectation;
    },
  );
}
