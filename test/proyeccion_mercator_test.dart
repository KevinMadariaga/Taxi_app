// `unproject` y `centroRotado` son nuevos (soporte para encuadrar el mapa de
// la preview cuando se conoce el destino del viaje) — sin cobertura previa.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

void main() {
  group('unproject', () {
    test('es la inversa de project (round-trip)', () {
      const puntos = [
        LatLng(4.7110, -74.0721), // Bogotá
        LatLng(10.9639, -74.7964), // Barranquilla
        LatLng(-33.4489, -70.6693), // Santiago
        LatLng(0, 0),
      ];

      for (final p in puntos) {
        final recuperado = ProyeccionMercator.unproject(
          ProyeccionMercator.project(p),
        );
        expect(recuperado.latitude, closeTo(p.latitude, 1e-6));
        expect(recuperado.longitude, closeTo(p.longitude, 1e-6));
      }
    });
  });

  group('centroRotado', () {
    test('sin rotación, es el centro del bounding box', () {
      const a = LatLng(4.60, -74.10);
      const b = LatLng(4.70, -74.00);

      final centro = ProyeccionMercator.centroRotado([a, b], 0);

      // La proyección Mercator es no lineal en latitud, así que el centro
      // del bbox EN PÍXELES no cae exactamente en el promedio aritmético de
      // las latitudes — la tolerancia cubre esa curvatura, no imprecisión
      // de punto flotante.
      expect(centro.latitude, closeTo((a.latitude + b.latitude) / 2, 1e-4));
      expect(centro.longitude, closeTo((a.longitude + b.longitude) / 2, 1e-6));
    });

    test('un solo punto es su propio centro, a cualquier rotación', () {
      const p = LatLng(4.65, -74.05);

      for (final rot in [0.0, 0.5, 1.0, -1.2]) {
        final centro = ProyeccionMercator.centroRotado([p], rot);
        expect(centro.latitude, closeTo(p.latitude, 1e-6));
        expect(centro.longitude, closeTo(p.longitude, 1e-6));
      }
    });
  });
}
