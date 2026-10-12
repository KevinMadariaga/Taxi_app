import '../entidades/viaje_entity.dart';

abstract class ViajeRepository {
  Stream<ViajeEntity> watchViaje(String viajeId);

  Future<void> actualizarEstado({
    required String viajeId,
    required String estado,
    Map<String, dynamic>? extra,
  });

  /// [motivo] queda en `cancelReason` (lo elige el conductor al cancelar).
  Future<void> cancelar({
    required String viajeId,
    required String canceladoPor,
    String? motivo,
  });

  /// Actualiza solo campos de `conductor.*` en la solicitud (nombre, foto,
  /// placa, fotoVehiculo) sin tocar `estado` — usado para propagar un cambio
  /// de perfil hecho a mitad de viaje. [datosConductor] son claves simples
  /// dentro de `conductor` (p. ej. `'nombre'`), no se pasan como dotted path.
  Future<void> actualizarInfoConductor({
    required String viajeId,
    required Map<String, dynamic> datosConductor,
  });
}
