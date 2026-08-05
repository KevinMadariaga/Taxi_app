import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Contrato de geocodificación inversa: coordenadas -> dirección legible.
/// Ninguna clase debe depender de la implementación concreta, solo de esta
/// interfaz.
abstract class GeocodificacionRepository {
  Future<String> direccionDesde(LatLng coordenada);
}
