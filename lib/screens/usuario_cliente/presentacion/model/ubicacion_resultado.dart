import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Resultado simple de búsqueda de ubicación usado en selección de destino.
class UbicacionResultado {
  /// Coordenadas de la ubicación. Null cuando viene de Google Places
  /// Autocomplete: ahí solo se conoce el `placeId` hasta que el usuario toca
  /// la sugerencia y se resuelve con Place Details (más barato que pedir
  /// detalles de todas las sugerencias mientras el usuario todavía escribe).
  final LatLng? location;

  /// Nombre o etiqueta asignada por el usuario (ej: "Casa", "Colegio").
  final String nombre;

  /// Dirección completa en texto de la ubicación.
  final String direccion;

  /// Presente solo en resultados de Google Places Autocomplete; se usa para
  /// resolver `location` bajo demanda con Place Details.
  final String? placeId;

  const UbicacionResultado({
    required this.location,
    required this.nombre,
    required this.direccion,
    this.placeId,
  });
}
