import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';

class CancelarViajeUseCase {
  CancelarViajeUseCase(this._repository);

  final ViajeRepository _repository;

  Future<void> call({required String viajeId, required String canceladoPor}) {
    return _repository.cancelar(viajeId: viajeId, canceladoPor: canceladoPor);
  }
}
