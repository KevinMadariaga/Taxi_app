import '../entidades/ubicacion_entity.dart';
import '../repositorios/ubicaciones_repository.dart';

class ObtenerFavoritosUseCase {
  ObtenerFavoritosUseCase(this._repository);

  final UbicacionesRepository _repository;

  Future<List<UbicacionEntity>> call({String tipo = 'Favorito'}) {
    return _repository.favoritosPorTipo(tipo);
  }
}
