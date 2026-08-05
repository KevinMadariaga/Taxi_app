import '../entidades/viaje_entity.dart';

abstract class ViajeRepository {
  Stream<ViajeEntity> watchViaje(String viajeId);

  Future<void> actualizarEstado({
    required String viajeId,
    required String estado,
    Map<String, dynamic>? extra,
  });

  Future<void> cancelar({
    required String viajeId,
    required String canceladoPor,
  });
}
