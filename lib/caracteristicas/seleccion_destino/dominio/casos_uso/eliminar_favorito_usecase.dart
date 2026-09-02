import '../repositorios/ubicaciones_repository.dart';

class EliminarFavoritoUseCase {
  EliminarFavoritoUseCase(this._repository);

  final UbicacionesRepository _repository;

  Future<void> call(String id) => _repository.eliminarFavorito(id);
}
