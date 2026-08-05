import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../entidades/ruta_resultado.dart';

/// Contrato de trazado de ruta entre dos puntos.
abstract class RutaRepository {
  Future<RutaResultado> trazar(LatLng origen, LatLng destino);
}
