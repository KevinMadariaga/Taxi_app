import '../entidades/ubicacion_entity.dart';
import '../repositorios/ubicaciones_repository.dart';

class ObtenerFavoritosUseCase {
  ObtenerFavoritosUseCase(this._repository);

  final UbicacionesRepository _repository;

  Future<List<UbicacionEntity>> call({int? limit}) {
    return _repository.favoritos(limit: limit);
  }
}
