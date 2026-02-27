
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Modelo para la configuración y estado del mapa del cliente.
/// Contiene datos de posición, zoom, marcadores, polilíneas y estado de carga.
class MapaClienteModel {
  final LatLng initialTarget;
  final double initialZoom;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool mapReady;

  const MapaClienteModel({
    this.initialTarget = const LatLng(8.2595534, -73.353469),
    this.initialZoom = 14.0,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.mapReady = false,
  });

  /// Retorna una copia del modelo con los cambios indicados.
  MapaClienteModel copyWith({
    LatLng? initialTarget,
    double? initialZoom,
    Set<Marker>? markers,
    Set<Polyline>? polylines,
    bool? mapReady,
  }) {
    return MapaClienteModel(
      initialTarget: initialTarget ?? this.initialTarget,
      initialZoom: initialZoom ?? this.initialZoom,
      markers: markers ?? this.markers,
      polylines: polylines ?? this.polylines,
      mapReady: mapReady ?? this.mapReady,
    );
  }
}



/// Resultado simple de búsqueda de ubicación usado en selección de destino.
class UbicacionResultado {
  /// Coordenadas de la ubicación.
  final LatLng? location;
  /// Nombre o etiqueta asignada por el usuario (ej: "Casa", "Colegio").
  final String nombre;
  /// Dirección completa en texto de la ubicación.
  final String direccion;

  const UbicacionResultado({
    required this.location,
    required this.nombre,
    required this.direccion,
  });
}
