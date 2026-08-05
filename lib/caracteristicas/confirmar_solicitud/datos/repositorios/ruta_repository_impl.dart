import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../../dominio/entidades/ruta_resultado.dart';
import '../../dominio/repositorios/ruta_repository.dart';

/// Traza la ruta real por calles (`MapService`, Directions/OSRM); si falla o
/// no hay datos, cae a una curva interpolada matemáticamente entre los dos
/// puntos para que siempre haya algo que dibujar.
class RutaRepositoryImpl implements RutaRepository {
  RutaRepositoryImpl({MapService? mapService})
    : _mapService = mapService ?? const MapService();

  final MapService _mapService;

  @override
  Future<RutaResultado> trazar(LatLng origen, LatLng destino) async {
    try {
      final puntos = await _mapService.getRoutePolyline(origen, destino);
      if (puntos.isNotEmpty) {
        final distanciaKm =
            _mapService.calcularDistanciaPolyline(puntos) / 1000.0;
        return RutaResultado(puntos: puntos, distanciaKm: distanciaKm);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'ruta_repository_impl');
    }
    return _fallbackMatematico(origen, destino);
  }

  RutaResultado _fallbackMatematico(LatLng origen, LatLng destino) {
    final straightMeters = MapHelper.distanceMeters(origen, destino);
    final segments = straightMeters < 1200
        ? 24
        : straightMeters < 4000
        ? 36
        : 48;
    final puntos = _interpolar(origen, destino, segments: segments);
    final distanciaKm = MapHelper.routeDistanceMeters(puntos) / 1000.0;
    return RutaResultado(puntos: puntos, distanciaKm: distanciaKm);
  }

  /// Curva suave perpendicular a la recta O->D (onda senoidal, máxima en el
  /// punto medio) para que el fallback no se vea como una línea recta.
  List<LatLng> _interpolar(
    LatLng origin,
    LatLng destination, {
    int segments = 20,
  }) {
    final safeSegments = math.max(2, segments);
    final points = <LatLng>[];

    final dLat = destination.latitude - origin.latitude;
    final dLng = destination.longitude - origin.longitude;
    final distance = math.sqrt((dLat * dLat) + (dLng * dLng));

    final normalLat = distance == 0 ? 0.0 : -dLng / distance;
    final normalLng = distance == 0 ? 0.0 : dLat / distance;
    final maxCurve = distance * 0.08;

    for (int i = 0; i <= safeSegments; i++) {
      final t = i / safeSegments;
      final baseLat =
          origin.latitude + (destination.latitude - origin.latitude) * t;
      final baseLng =
          origin.longitude + (destination.longitude - origin.longitude) * t;

      final curveFactor = math.sin(math.pi * t) * maxCurve;
      final lat = baseLat + (normalLat * curveFactor);
      final lng = baseLng + (normalLng * curveFactor);
      points.add(LatLng(lat, lng));
    }

    return points;
  }
}
