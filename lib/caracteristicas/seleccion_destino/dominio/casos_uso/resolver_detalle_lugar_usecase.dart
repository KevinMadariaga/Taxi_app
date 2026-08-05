import '../entidades/ubicacion_entity.dart';
import '../repositorios/lugares_repository.dart';

/// Resuelve coordenadas para una sugerencia de Google Places que solo trae
/// `placeId` (Autocomplete no incluye lat/lng, hace falta un Place Details).
class ResolverDetalleLugarUseCase {
  ResolverDetalleLugarUseCase(this._repository);

  final LugaresRepository _repository;

  Future<UbicacionEntity?> call(String placeId) {
    return _repository.detalle(placeId);
  }
}
