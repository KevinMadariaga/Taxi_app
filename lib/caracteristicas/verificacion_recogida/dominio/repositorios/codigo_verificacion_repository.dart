import '../entidades/codigo_verificacion_entity.dart';

/// Acceso a datos puro — sin reglas de negocio (idempotencia, comparación,
/// conteo de intentos viven en los casos de uso).
abstract class CodigoVerificacionRepository {
  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId);

  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId);

  Future<void> guardarCodigo(String viajeId, CodigoVerificacionEntity codigo);

  Future<void> marcarValidado(String viajeId);

  Future<void> incrementarIntentoFallido(String viajeId);
}
