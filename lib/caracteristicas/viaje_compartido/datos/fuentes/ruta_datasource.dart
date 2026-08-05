import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/features/trip_tracking_cliente/services/map_service.dart'
    as feature_map;

/// Envoltorio delgado sobre `feature_map.MapService` (ganador de la
/// consolidación de ruteo — ver plan): único con los 3 niveles de fallback
/// (Directions vía Cloud Function → OSRM → línea recta) y caché de 8s.
/// Reemplaza a `DriverRouteService` (tenía su propia llamada OSRM
/// duplicada) y al uso de `map_service_adapter.dart` para este flujo.
class RutaDatasource {
  RutaDatasource({feature_map.MapService? mapService})
    : _mapService = mapService ?? feature_map.MapService();

  final feature_map.MapService _mapService;

  Future<List<LatLng>> obtenerRuta({
    required LatLng origen,
    required LatLng destino,
  }) {
    return _mapService.fetchRoadPolyline(from: origen, to: destino);
  }

  double distanciaRuta(List<LatLng> puntos) =>
      _mapService.routeDistanceMeters(puntos);

  Duration etaDesdeDistancia(
    double distanciaMetros, {
    double velocidadPromedioKmh = 26,
  }) => _mapService.etaFromDistance(
    distanciaMetros,
    averageSpeedKmh: velocidadPromedioKmh,
  );

  String formatearDistancia(double metros) =>
      _mapService.formatDistance(metros);

  String formatearEta(Duration eta) => _mapService.formatEta(eta);
}
