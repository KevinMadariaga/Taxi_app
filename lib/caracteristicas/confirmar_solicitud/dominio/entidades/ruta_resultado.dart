import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Resultado de trazar una ruta entre dos puntos: los puntos físicos (por
/// calle si se pudo, línea curva interpolada si no) y la distancia estimada.
class RutaResultado {
  const RutaResultado({required this.puntos, required this.distanciaKm});

  final List<LatLng> puntos;
  final double distanciaKm;
}
