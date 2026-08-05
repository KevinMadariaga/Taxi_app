import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';

class ActualizarEstadoViajeParams {
  const ActualizarEstadoViajeParams({
    required this.viajeId,
    required this.estado,
    this.extra,
  });

  final String viajeId;
  final String estado;
  final Map<String, dynamic>? extra;
}

class ActualizarEstadoViajeUseCase {
  ActualizarEstadoViajeUseCase(this._repository);

  final ViajeRepository _repository;

  Future<void> call(ActualizarEstadoViajeParams params) {
    return _repository.actualizarEstado(
      viajeId: params.viajeId,
      estado: params.estado,
      extra: params.extra,
    );
  }
}
