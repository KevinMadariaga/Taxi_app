import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../entidades/ruta_resultado.dart';
import '../repositorios/ruta_repository.dart';

class TrazarRutaUseCase {
  TrazarRutaUseCase(this._repository);

  final RutaRepository _repository;

  Future<RutaResultado> call(LatLng origen, LatLng destino) {
    return _repository.trazar(origen, destino);
  }
}
