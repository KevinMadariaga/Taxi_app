import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Resultado devuelto al confirmar una ubicación en
/// `SeleccionarUbicacionMapaView`.
class SeleccionUbicacionResult {
  const SeleccionUbicacionResult({required this.position, this.direccion});

  final LatLng position;
  final String? direccion;
}
