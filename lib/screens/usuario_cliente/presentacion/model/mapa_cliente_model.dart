import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Modelo para la pantalla de mapa cliente
/// 
/// Contiene datos relacionados con la visualización del mapa,
/// marcadores, polilíneas y configuración general.
class MapaClienteModel {
  /// Posición inicial del mapa
  final LatLng initialTarget;

  /// Zoom inicial
  final double initialZoom;

  /// Marcadores a mostrar en el mapa
  final Set<Marker> markers;

  /// Polilíneas (rutas) a mostrar en el mapa
  final Set<Polyline> polylines;

  /// Indica si el mapa está listo
  final bool mapReady;

  /// Constructor
  MapaClienteModel({
    this.initialTarget = const LatLng(8.2595534, -73.353469),
    this.initialZoom = 14.0,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.mapReady = false,
  });

  /// Método para copiar con cambios opcionales
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
  final LatLng? location;
  final String direccion;

  UbicacionResultado({required this.location, required this.direccion});
}
