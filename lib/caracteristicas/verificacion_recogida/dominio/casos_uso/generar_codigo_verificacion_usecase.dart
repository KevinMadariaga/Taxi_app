import 'dart:math';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';

/// Genera el código de 4 dígitos al momento en que el conductor reporta
/// llegada (asignado→enEspera) — mismo patrón de `Random` que
/// `generarCredencialesConductor`
/// (`features/phone_auth/services/user_data_service.dart`), sin el
/// retry-loop de unicidad de ese precedente: acá la unicidad solo importa
/// dentro del propio viaje (el conductor únicamente valida contra SU
/// solicitud), no entre documentos.
///
/// Idempotente: si ya existe un código generado para el viaje, lo devuelve
/// tal cual en vez de sobreescribirlo (protege contra doble tap/retry).
class GenerarCodigoVerificacionUseCase {
  GenerarCodigoVerificacionUseCase(this._repository, {Random? random})
    : _random = random ?? Random();

  final CodigoVerificacionRepository _repository;
  final Random _random;

  Future<CodigoVerificacionEntity> call(String viajeId) async {
    final existente = await _repository.obtenerCodigo(viajeId);
    if (existente != null && existente.generado) {
      return existente;
    }

    final codigo = (1000 + _random.nextInt(9000)).toString();
    final nuevo = CodigoVerificacionEntity(
      codigo: codigo,
      generadoEn: DateTime.now(),
      validadoEn: null,
      intentosFallidos: 0,
    );

    await _repository.guardarCodigo(viajeId, nuevo);
    return nuevo;
  }
}
