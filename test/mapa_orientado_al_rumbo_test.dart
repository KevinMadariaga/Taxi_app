import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

/// El mapa del viaje del conductor se dibuja rotado para que el rumbo
/// conductor→cliente apunte hacia arriba. Estos tests fijan las dos cosas de
/// las que depende que se vea bien: que el conductor SIEMPRE quede abajo y el
/// cliente arriba (venga de donde venga), y que el zoom calculado deje ambos
/// dentro del recuadro visible.

/// Posición en pantalla (px respecto al centro, +y hacia abajo) de [punto]
/// con el lienzo rotado [rotacionRad].
Offset _enPantalla({
  required LatLng center,
  required LatLng punto,
  required double zoom,
  required double rotacionRad,
}) {
  final o = ProyeccionMercator.pixelOffset(
    center: center,
    point: punto,
    zoom: zoom,
  );
  final cos = math.cos(rotacionRad);
  final sin = math.sin(rotacionRad);
  return Offset(o.dx * cos - o.dy * sin, o.dx * sin + o.dy * cos);
}

void main() {
  const rumbos = <String, LatLng>{
    'cliente al norte': LatLng(4.65, -74.08),
    'cliente al sur': LatLng(4.55, -74.08),
    'cliente al este': LatLng(4.60, -74.03),
    'cliente al oeste': LatLng(4.60, -74.13),
    'cliente al noreste': LatLng(4.64, -74.04),
    'cliente al suroeste': LatLng(4.56, -74.12),
  };

  const driver = LatLng(4.60, -74.08);

  rumbos.forEach((nombre, cliente) {
    test('$nombre: el conductor queda abajo y el cliente arriba', () {
      final rumbo = ProyeccionMercator.bearingDegrees(driver, cliente);
      final rotacion = ProyeccionMercator.rotacionParaRumboArriba(rumbo);

      // Mismo centro que usa el widget al orientar al rumbo.
      const fraccion = 0.58;
      final center = LatLng(
        driver.latitude + (cliente.latitude - driver.latitude) * fraccion,
        driver.longitude + (cliente.longitude - driver.longitude) * fraccion,
      );

      final pDriver = _enPantalla(
        center: center,
        punto: driver,
        zoom: 14,
        rotacionRad: rotacion,
      );
      final pCliente = _enPantalla(
        center: center,
        punto: cliente,
        zoom: 14,
        rotacionRad: rotacion,
      );

      // +y es hacia abajo: el conductor debe tener y mayor que el cliente.
      expect(
        pDriver.dy,
        greaterThan(pCliente.dy),
        reason: '$nombre: el conductor no quedó por debajo del cliente',
      );

      // Y ambos alineados sobre el eje vertical de la pantalla: la traza sale
      // del conductor hacia arriba, no en diagonal.
      expect(pDriver.dx.abs(), lessThan(1.0), reason: '$nombre: conductor');
      expect(pCliente.dx.abs(), lessThan(1.0), reason: '$nombre: cliente');

      // El corrimiento del centro deja al conductor más abajo que al cliente
      // arriba: hay más recorrido a la vista por delante.
      expect(pDriver.dy.abs(), greaterThan(pCliente.dy.abs()));
    });
  });

  test('el zoom rotado deja conductor, cliente y ruta dentro del recuadro', () {
    const cliente = LatLng(4.64, -74.04);
    const width = 390.0;
    const height = 420.0;
    const margenH = 56.0;
    const margenV = 72.0;

    // Ruta que se curva hacia un lado — el caso que el encuadre de dos puntos
    // dejaba salirse por el costado.
    const ruta = <LatLng>[
      LatLng(4.61, -74.075),
      LatLng(4.625, -74.055),
      LatLng(4.632, -74.048),
    ];

    final rumbo = ProyeccionMercator.bearingDegrees(driver, cliente);
    final rotacion = ProyeccionMercator.rotacionParaRumboArriba(rumbo);
    const fraccion = 0.58;
    final center = LatLng(
      driver.latitude + (cliente.latitude - driver.latitude) * fraccion,
      driver.longitude + (cliente.longitude - driver.longitude) * fraccion,
    );

    final zoom = ProyeccionMercator.boundsZoomRotado(
      const [driver, ...ruta, cliente],
      center: center,
      rotacionRad: rotacion,
      widthPx: width,
      heightPx: height,
      margenHorizontal: margenH,
      margenVertical: margenV,
    ).floorToDouble();

    for (final punto in const [driver, ...ruta, cliente]) {
      final p = _enPantalla(
        center: center,
        punto: punto,
        zoom: zoom,
        rotacionRad: rotacion,
      );
      expect(
        p.dx.abs(),
        lessThanOrEqualTo((width - margenH) / 2),
        reason: 'punto $punto se sale por el costado',
      );
      expect(
        p.dy.abs(),
        lessThanOrEqualTo((height - margenV) / 2),
        reason: 'punto $punto se sale por arriba/abajo',
      );
    }
  });

  test('sin rotación el rumbo norte deja el mapa tal cual', () {
    expect(ProyeccionMercator.rotacionParaRumboArriba(0), 0);
    expect(
      ProyeccionMercator.bearingDegrees(driver, const LatLng(4.65, -74.08)),
      closeTo(0, 0.01),
    );
    expect(
      ProyeccionMercator.bearingDegrees(driver, const LatLng(4.60, -74.03)),
      closeTo(90, 0.5),
    );
  });
}
