import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';

enum ResultadoValidacionCodigo { correcto, incorrecto, noGenerado }

/// Valida el código que el conductor ingresa contra el generado para el
/// viaje. Sin lockout tras varios intentos fallidos (`intentosFallidos` se
/// persiste igual, disponible para revisión antifraude a futuro) — no hay
/// dinero en juego en este checkpoint, más vale no varar un viaje real por
/// un error de tipeo.
class ValidarCodigoVerificacionUseCase {
  ValidarCodigoVerificacionUseCase(this._repository);

  final CodigoVerificacionRepository _repository;

  Future<ResultadoValidacionCodigo> call({
    required String viajeId,
    required String codigoIngresado,
  }) async {
    final actual = await _repository.obtenerCodigo(viajeId);
    if (actual == null || !actual.generado) {
      return ResultadoValidacionCodigo.noGenerado;
    }

    final coincide = actual.codigo.trim() == codigoIngresado.trim();
    if (coincide) {
      await _repository.marcarValidado(viajeId);
      return ResultadoValidacionCodigo.correcto;
    }

    await _repository.incrementarIntentoFallido(viajeId);
    return ResultadoValidacionCodigo.incorrecto;
  }
}
