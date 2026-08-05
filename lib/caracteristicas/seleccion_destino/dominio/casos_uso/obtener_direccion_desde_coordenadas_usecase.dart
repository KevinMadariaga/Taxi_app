import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../repositorios/geocodificacion_repository.dart';

/// Resuelve la dirección legible para un punto del mapa.
class ObtenerDireccionDesdeCoordenadasUseCase {
  ObtenerDireccionDesdeCoordenadasUseCase(this._repository);

  final GeocodificacionRepository _repository;

  Future<String> call(LatLng coordenada) {
    return _repository.direccionDesde(coordenada);
  }
}
