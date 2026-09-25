import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

void main() {
  test('bearingDegrees: norte 0°, este ~90°', () {
    const a = LatLng(8.24, -73.35);
    expect(
      ProyeccionMercator.bearingDegrees(a, const LatLng(8.25, -73.35)),
      closeTo(0, 0.5),
    );
    expect(
      ProyeccionMercator.bearingDegrees(a, const LatLng(8.24, -73.34)),
      closeTo(90, 0.5),
    );
  });

  test(
    'encuadre rotado: ruta urbana de ~2 km queda cerca y cambia con el rumbo',
    () {
      // Ruta norte-sur de ~2,2 km en Ocaña, tarjeta de mapa típica de teléfono.
      const a = LatLng(8.2350, -73.3560);
      const b = LatLng(8.2550, -73.3560);
      const centro = LatLng(8.2450, -73.3560);
      double zoom(double rumbo) => ProyeccionMercator.boundsZoomRotado(
        [a, b],
        center: centro,
        rotacionRad: ProyeccionMercator.rotacionParaRumboArriba(rumbo),
        widthPx: 340,
        heightPx: 330,
        margenHorizontal: 70,
        margenVertical: 130,
        zoomMax: 17.5,
      );

      // Mirando al norte la ruta va a lo alto de la tarjeta.
      expect(zoom(0), inInclusiveRange(13.5, 15.5));
      // Mirando al este la ruta queda atravesada: cabe con más zoom (hay más
      // ancho útil que alto útil).
      expect(zoom(90), greaterThan(zoom(0)));
    },
  );
}
