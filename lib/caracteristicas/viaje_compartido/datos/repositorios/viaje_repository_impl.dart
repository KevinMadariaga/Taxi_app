import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';
import 'package:taxi_app/core/services/solicitud_firestore_datasource.dart';

import '../modelos/viaje_model.dart';

/// Implementación única sobre `SolicitudFirestoreDatasource` (ganador de la
/// consolidación de escritura de estado — ver plan): normaliza vía
/// `SolicitudEstado.normalize` y estampa `completedAt` al llegar a
/// `completado`, algo que la ruta de escritura legacy de `driver_trip`
/// (`DriverTripFirestoreService.updateTripStatus`) no hacía.
class ViajeRepositoryImpl implements ViajeRepository {
  ViajeRepositoryImpl({SolicitudFirestoreDatasource? datasource})
    : _datasource = datasource ?? SolicitudFirestoreDatasource();

  final SolicitudFirestoreDatasource _datasource;

  @override
  Stream<ViajeEntity> watchViaje(String viajeId) {
    return _datasource.watch(viajeId).map(ViajeModel.fromSnapshot);
  }

  @override
  Future<void> actualizarEstado({
    required String viajeId,
    required String estado,
    Map<String, dynamic>? extra,
  }) {
    return _datasource.actualizarEstado(
      solicitudId: viajeId,
      estado: estado,
      extra: extra,
    );
  }

  @override
  Future<void> cancelar({
    required String viajeId,
    required String canceladoPor,
  }) {
    return _datasource.marcarCancelada(
      solicitudId: viajeId,
      canceladoPor: canceladoPor,
    );
  }
}
