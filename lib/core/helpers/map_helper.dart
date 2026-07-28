import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Helper para lógica de mapa que no depende de la UI:
///
/// - Carga de íconos personalizados
/// - Cálculo de distancias
/// - Cálculo de rumbos (bearing)
/// - Distancia total de una ruta
class MapHelper {
  MapHelper._();

  /// Carga un ícono de marcador desde assets con un tamaño y DPR razonables.
  static Future<BitmapDescriptor> loadMarkerIcon(
    String assetPath, {
    Size size = const Size(48, 48),
    double? devicePixelRatio,
  }) async {
    // Use a neutral devicePixelRatio for marker generation by default to avoid
    // producing oversized icons on high-density iOS displays. Callers may
    // still override `devicePixelRatio` when needed.
    final usedDpr = devicePixelRatio ?? 1.0;
    return BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: size, devicePixelRatio: usedDpr),
      assetPath,
    );
  }

  /// Distancia en metros entre dos puntos usando Geolocator.
  ///
  /// Única fuente de cálculo de distancia del proyecto: antes la fórmula de
  /// Haversine estaba reimplementada a mano (con resultados numéricamente
  /// equivalentes) en `TripRouteMathService`, `MapService`,
  /// `DriverRouteService`, `RutaClienteDestinoView`, `preview_route_controller`
  /// y `pending_solicitudes_controller` — todos delegan aquí ahora.
  static double distanceMeters(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Formatea una distancia en metros como "123 m" o "1.23 km" (umbral 1000m).
  /// Única fuente: antes duplicada idéntica en `TripRouteMathService`,
  /// `MapService`, `DriverRouteService` y `RutaClienteDestinoView`.
  static String formatDistanceMeters(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Distancia total en metros de una lista de puntos (ruta polilínea).
  static double routeDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }

  /// Calcula el rumbo (bearing) en grados desde `from` hacia `to`.
  /// Devuelve un valor en [0, 360).
  ///
  /// Única fuente de la fórmula de bearing del proyecto: antes estaba
  /// reimplementada de forma idéntica en `TripRouteMathService`,
  /// `RutaClienteDestinoViewModel`, `RutaDestinoViewModel` y
  /// `preview_route_controller` (y con una variante plana menos precisa en
  /// `RutaClienteDestinoView`) — todos delegan aquí ahora.
  static double bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }

  /// Interpola angularmente de `from` a `to` por el camino más corto (nunca
  /// más de 180°), avanzando una fracción `t` (0..1). Usado para suavizar la
  /// rotación de un marker tick a tick sin que "gire por el lado largo" al
  /// cruzar el límite 0°/360°.
  static double lerpAngle(double from, double to, double t) {
    final diff = ((to - from + 540) % 360) - 180;
    final result = (from + diff * t) % 360;
    return result < 0 ? result + 360 : result;
  }
}
