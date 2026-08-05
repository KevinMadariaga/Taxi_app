import '../entidades/ubicacion_entity.dart';
import '../repositorios/historial_destinos_repository.dart';

class ObtenerHistorialDestinosUseCase {
  ObtenerHistorialDestinosUseCase(this._repository);

  final HistorialDestinosRepository _repository;

  Future<List<UbicacionEntity>> call() => _repository.obtener();
}
