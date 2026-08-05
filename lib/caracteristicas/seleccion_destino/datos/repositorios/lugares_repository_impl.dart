import 'package:taxi_app/core/services/places_search_service.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../../dominio/repositorios/lugares_repository.dart';

/// Delega en [PlacesSearchService] (Cloud Functions `searchPlacesOcana` /
/// `getPlaceDetails` — la key de Google nunca vive en el cliente).
class LugaresRepositoryImpl implements LugaresRepository {
  LugaresRepositoryImpl({PlacesSearchService? service})
    : _service = service ?? const PlacesSearchService();

  final PlacesSearchService _service;

  @override
  Future<List<UbicacionEntity>> buscar(String query) async {
    final predicciones = await _service.buscar(query);
    return predicciones
        .map(
          (p) => UbicacionEntity(
            nombre: p.mainText,
            direccion: p.secondaryText.isNotEmpty
                ? p.secondaryText
                : p.mainText,
            placeId: p.placeId,
          ),
        )
        .toList();
  }

  @override
  Future<UbicacionEntity?> detalle(String placeId) async {
    final detalles = await _service.obtenerDetalles(placeId);
    if (detalles == null) return null;
    return UbicacionEntity(
      nombre: detalles.name,
      direccion: detalles.formattedAddress,
      position: detalles.location,
      placeId: placeId,
    );
  }
}
