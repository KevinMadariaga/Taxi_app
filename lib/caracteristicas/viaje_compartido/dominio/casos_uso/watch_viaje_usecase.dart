import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';

class WatchViajeUseCase {
  WatchViajeUseCase(this._repository);

  final ViajeRepository _repository;

  Stream<ViajeEntity> call(String viajeId) => _repository.watchViaje(viajeId);
}
