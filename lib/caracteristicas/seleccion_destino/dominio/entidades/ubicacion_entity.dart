import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Ubicación de dominio: una sugerencia de destino (guardada en Firestore o
/// resuelta desde Google Places), o un favorito guardado del usuario.
///
/// [position] es `null` cuando viene de Google Places Autocomplete y todavía
/// no se resolvió [placeId] a coordenadas (requiere un round-trip a
/// `PlaceDetails` antes de poder navegar con esta ubicación).
class UbicacionEntity {
  const UbicacionEntity({
    required this.nombre,
    required this.direccion,
    this.position,
    this.placeId,
    this.tipo,
  });

  final String nombre;
  final String direccion;
  final LatLng? position;
  final String? placeId;
  final String? tipo;

  UbicacionEntity copyWith({
    String? nombre,
    String? direccion,
    LatLng? position,
    String? placeId,
    String? tipo,
  }) {
    return UbicacionEntity(
      nombre: nombre ?? this.nombre,
      direccion: direccion ?? this.direccion,
      position: position ?? this.position,
      placeId: placeId ?? this.placeId,
      tipo: tipo ?? this.tipo,
    );
  }
}
