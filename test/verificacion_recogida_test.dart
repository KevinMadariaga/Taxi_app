// Tests unitarios de los casos de uso de verificacion_recogida — puros
// (dependen solo de la interfaz `CodigoVerificacionRepository`, sin
// Firestore), cubren: generación idempotente y validación
// correcto/incorrecto/no-generado con conteo de intentos fallidos.

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';

class _FakeCodigoVerificacionRepository
    implements CodigoVerificacionRepository {
  final Map<String, CodigoVerificacionEntity> _porViaje = {};
  int guardarCodigoLlamadas = 0;

  @override
  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId) async {
    return _porViaje[viajeId];
  }

  @override
  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId) {
    return Stream.value(_porViaje[viajeId]);
  }

  @override
  Future<void> guardarCodigo(
    String viajeId,
    CodigoVerificacionEntity codigo,
  ) async {
    guardarCodigoLlamadas++;
    _porViaje[viajeId] = codigo;
  }

  @override
  Future<void> marcarValidado(String viajeId) async {
    final actual = _porViaje[viajeId];
    if (actual == null) return;
    _porViaje[viajeId] = actual.copyWith(validadoEn: DateTime.now());
  }

  @override
  Future<void> incrementarIntentoFallido(String viajeId) async {
    final actual = _porViaje[viajeId];
    if (actual == null) return;
    _porViaje[viajeId] = actual.copyWith(
      intentosFallidos: actual.intentosFallidos + 1,
    );
  }
}

void main() {
  group('GenerarCodigoVerificacionUseCase', () {
    test('genera un código de 4 dígitos y lo persiste', () async {
      final repo = _FakeCodigoVerificacionRepository();
      final usecase = GenerarCodigoVerificacionUseCase(repo);

      final resultado = await usecase('viaje-1');

      expect(resultado.codigo.length, 4);
      expect(int.tryParse(resultado.codigo), isNotNull);
      expect(repo.guardarCodigoLlamadas, 1);
    });

    test('es idempotente: no sobreescribe un código ya generado', () async {
      final repo = _FakeCodigoVerificacionRepository();
      final usecase = GenerarCodigoVerificacionUseCase(repo);

      final primero = await usecase('viaje-1');
      final segundo = await usecase('viaje-1');

      expect(segundo.codigo, primero.codigo);
      expect(repo.guardarCodigoLlamadas, 1);
    });
  });

  group('ValidarCodigoVerificacionUseCase', () {
    test('devuelve noGenerado si el viaje no tiene código', () async {
      final repo = _FakeCodigoVerificacionRepository();
      final usecase = ValidarCodigoVerificacionUseCase(repo);

      final resultado = await usecase(
        viajeId: 'viaje-1',
        codigoIngresado: '1234',
      );

      expect(resultado, ResultadoValidacionCodigo.noGenerado);
    });

    test(
      'devuelve correcto y marca validado cuando el código coincide',
      () async {
        final repo = _FakeCodigoVerificacionRepository();
        await GenerarCodigoVerificacionUseCase(repo)('viaje-1');
        final codigoReal = (await repo.obtenerCodigo('viaje-1'))!.codigo;
        final usecase = ValidarCodigoVerificacionUseCase(repo);

        final resultado = await usecase(
          viajeId: 'viaje-1',
          codigoIngresado: codigoReal,
        );

        expect(resultado, ResultadoValidacionCodigo.correcto);
        final actual = await repo.obtenerCodigo('viaje-1');
        expect(actual!.validado, isTrue);
      },
    );

    test(
      'devuelve incorrecto e incrementa intentosFallidos cuando no coincide',
      () async {
        final repo = _FakeCodigoVerificacionRepository();
        await GenerarCodigoVerificacionUseCase(repo)('viaje-1');
        final codigoReal = (await repo.obtenerCodigo('viaje-1'))!.codigo;
        final codigoIncorrecto = codigoReal == '0000' ? '1111' : '0000';
        final usecase = ValidarCodigoVerificacionUseCase(repo);

        final resultado = await usecase(
          viajeId: 'viaje-1',
          codigoIngresado: codigoIncorrecto,
        );

        expect(resultado, ResultadoValidacionCodigo.incorrecto);
        final actual = await repo.obtenerCodigo('viaje-1');
        expect(actual!.intentosFallidos, 1);
        expect(actual.validado, isFalse);
      },
    );

    test('no bloquea tras varios intentos fallidos (sin lockout)', () async {
      final repo = _FakeCodigoVerificacionRepository();
      await GenerarCodigoVerificacionUseCase(repo)('viaje-1');
      final codigoReal = (await repo.obtenerCodigo('viaje-1'))!.codigo;
      final codigoIncorrecto = codigoReal == '0000' ? '1111' : '0000';
      final usecase = ValidarCodigoVerificacionUseCase(repo);

      for (var i = 0; i < 5; i++) {
        await usecase(viajeId: 'viaje-1', codigoIngresado: codigoIncorrecto);
      }
      final resultado = await usecase(
        viajeId: 'viaje-1',
        codigoIngresado: codigoReal,
      );

      expect(resultado, ResultadoValidacionCodigo.correcto);
      final actual = await repo.obtenerCodigo('viaje-1');
      expect(actual!.intentosFallidos, 5);
      expect(actual.validado, isTrue);
    });
  });
}
