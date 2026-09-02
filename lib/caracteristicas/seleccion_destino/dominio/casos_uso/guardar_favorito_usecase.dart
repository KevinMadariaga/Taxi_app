import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../repositorios/ubicaciones_repository.dart';

class GuardarFavoritoUseCase {
  GuardarFavoritoUseCase(this._repository);

  final UbicacionesRepository _repository;

  /// Devuelve el id del favorito creado.
  Future<String> call({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    String tipo = 'Favorito',
  }) {
    return _repository.guardarFavorito(
      nombre: nombre,
      direccion: direccion,
      ubicacion: ubicacion,
      tipo: tipo,
    );
  }
}
