import 'dart:math' as math;
import 'dart:ui';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Proyección Web Mercator (mismas fórmulas que usa Google Maps/Static Maps
/// internamente para pasar de lat/lng a píxeles) — para overlayear íconos
/// propios (assets locales) sobre una imagen de Google Static Maps, que no
/// puede referenciar assets locales en su parámetro `markers=`.
///
/// Única fuente de esta matemática: antes vivía duplicada como métodos
/// privados de `_BuscandoTaxiStaticMap`
/// (`lib/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart`).
class ProyeccionMercator {
  ProyeccionMercator._();

  static const double zoomMinPorDefecto = 3;
  static const double zoomMaxPorDefecto = 20;

  static Offset project(LatLng point) {
    final double sinLat = math
        .sin(point.latitude * math.pi / 180)
        .clamp(-0.9999, 0.9999)
        .toDouble();
    final double x = 128.0 + point.longitude * (256.0 / 360.0);
    final double y =
        128.0 -
        (math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) * 256.0;
    return Offset(x, y);
  }

  /// Offset en píxeles (respecto a [center]) de [point], al [zoom] dado.
  /// Misma unidad de píxeles que el parámetro `size` de Static Maps: el
  /// `scale=2` de retina no afecta esta cuenta, solo aumenta la densidad de
  /// la imagen, no el área geográfica que cubre.
  static Offset pixelOffset({
    required LatLng center,
    required LatLng point,
    required double zoom,
  }) {
    final double scale = math.pow(2, zoom).toDouble();
    final Offset centerPx = project(center);
    final Offset pointPx = project(point);
    return Offset(
      (pointPx.dx - centerPx.dx) * scale,
      (pointPx.dy - centerPx.dy) * scale,
    );
  }

  static double _latRad(double lat) {
    final double sinLat = math
        .sin(lat * math.pi / 180)
        .clamp(-0.9999, 0.9999)
        .toDouble();
    final double radX2 = math.log((1.0 + sinLat) / (1.0 - sinLat)) / 2.0;
    return radX2.clamp(-math.pi, math.pi) / 2.0;
  }

  /// Zoom continuo que encuadra el bounding box de [a] y [b] dentro de un
  /// viewport de [widthPx]x[heightPx] (fórmula estándar `getBoundsZoomLevel`
  /// de Google): el zoom sigue bajando de forma continua a medida que crece
  /// la distancia entre los puntos, sin techo/piso a mitad de escala.
  static double boundsZoom(
    LatLng a,
    LatLng b,
    double widthPx,
    double heightPx, {
    double zoomMin = zoomMinPorDefecto,
    double zoomMax = zoomMaxPorDefecto,
    double margenHorizontal = 90.0,
    double margenVertical = 120.0,
  }) {
    const double worldDim = 256.0;
    // Margen para que los íconos (que tienen alto/ancho propio, no son
    // puntos infinitesimales) no queden pegados al borde de la imagen.
    final double effectiveWidth = math.max(40.0, widthPx - margenHorizontal);
    final double effectiveHeight = math.max(40.0, heightPx - margenVertical);

    final LatLng sw = LatLng(
      math.min(a.latitude, b.latitude),
      math.min(a.longitude, b.longitude),
    );
    final LatLng ne = LatLng(
      math.max(a.latitude, b.latitude),
      math.max(a.longitude, b.longitude),
    );

    final double latFraction =
        (_latRad(ne.latitude) - _latRad(sw.latitude)) / math.pi;
    final double lngDiff = ne.longitude - sw.longitude;
    final double lngFraction =
        (lngDiff < 0 ? lngDiff + 360.0 : lngDiff) / 360.0;

    double zoomFor(double mapPx, double fraction) {
      if (fraction <= 0) return zoomMax;
      return math.log(mapPx / worldDim / fraction) / math.ln2;
    }

    final double latZoom = zoomFor(effectiveHeight, latFraction.abs());
    final double lngZoom = zoomFor(effectiveWidth, lngFraction.abs());

    return math.min(latZoom, lngZoom).clamp(zoomMin, zoomMax).toDouble();
  }
}
