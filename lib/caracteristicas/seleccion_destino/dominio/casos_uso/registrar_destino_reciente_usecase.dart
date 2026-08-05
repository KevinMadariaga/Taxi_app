import '../entidades/ubicacion_entity.dart';
import '../repositorios/historial_destinos_repository.dart';

class RegistrarDestinoRecienteUseCase {
  RegistrarDestinoRecienteUseCase(this._repository);

  final HistorialDestinosRepository _repository;

  Future<void> call(UbicacionEntity destino) => _repository.registrar(destino);
}
