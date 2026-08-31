// Sin cobertura previa (verificado con grep antes de escribir este archivo).
//
// Usa `fake_async` para controlar el `Timer.periodic(50ms)` sin esperas
// reales — PERO `fake_async` no intercepta `DateTime.now()` (ya documentado
// en `test/buscando_taxi_viewmodel_test.dart`: "el problema de DateTime.now()
// no interceptado que sí aplicaba al motor de movimiento"). Por eso
// `ConductorMovementSimulator` ahora acepta un reloj inyectable (`now:`) —
// se le pasa `FakeAsync.getClock(...).now`, que sí avanza junto con
// `async.elapse(...)`.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/features/trip_tracking_cliente/controllers/conductor_movement_simulator.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_route_math_service.dart';

const _mathService = TripRouteMathService();

void main() {
  group('ConductorMovementSimulator — velocidad de crucero', () {
    test(
      'ruta con giro: llega al target dentro de la MISMA ventana de tiempo '
      'real que separó los dos pings — antes calibraba la velocidad contra '
      'la línea recta (más corta que el camino real por calles), así que un '
      'giro dejaba al marcador sistemáticamente atrasado respecto al ping '
      'siguiente',
      () {
        fakeAsync((async) {
          final clock = async.getClock(DateTime(2026, 1, 1));
          final sim = ConductorMovementSimulator(now: clock.now);
          addTearDown(sim.dispose);

          // L: A -> B (este, ~8m) -> C (norte, ~8m). Camino real ~16m,
          // línea recta A-C ~11.3m (Pitágoras) — la diferencia es la que
          // antes se ignoraba al calcular la velocidad.
          const a = LatLng(4.60000, -74.08000);
          const b = LatLng(4.60000, -74.0799279);
          const c = LatLng(4.6000719, -74.0799279);
          final ruta = _mathService.densifyPolyline([a, b, c]);
          sim.setFullRoute(ruta);

          // Primer ping: se aplica directo, sin animar.
          sim.enqueueTarget(a);
          expect(sim.currentPosition, a);

          // Gap real entre pings de GPS: 3s (típico del throttle de
          // TrackingService, que no manda más de un punto cada 5s, pero un
          // punto puede tardar más si hay poco movimiento).
          const gap = Duration(seconds: 3);
          async.elapse(gap);
          sim.enqueueTarget(c);

          // Si para cuando llegaría el PRÓXIMO ping (otro `gap` después) el
          // marcador ya está pegado a C, no se atrasó. Con la línea recta
          // (bug), la velocidad calculada (11.3m/3s ≈ 3.77 m/s) no alcanza a
          // cubrir los 16m reales del camino en esa ventana — quedaría a
          // ~4.7m de C. Con la distancia de ruta (fix), la velocidad
          // calculada (16m/3s ≈ 5.33 m/s, piso 6.0 m/s) sí alcanza.
          async.elapse(gap);

          final distanciaAC = _mathService.haversineMeters(
            sim.currentPosition!,
            c,
          );
          expect(distanciaAC, lessThan(3.0));
        });
      },
    );
  });

  group('ConductorMovementSimulator — piso y techo de velocidad', () {
    test('techo: un salto rápido pero < 200m no se anima a velocidad sin límite', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 1, 1));
        final sim = ConductorMovementSimulator(now: clock.now);
        addTearDown(sim.dispose);

        const a = LatLng(4.60000, -74.08000);
        // ~150m al este, bien bajo el umbral de salto grande (200m).
        const b = LatLng(4.60000, -74.078648);

        sim.enqueueTarget(a);
        // Gap de 1s -> velocidad cruda implícita ~150 m/s, muy por encima de
        // cualquier techo razonable.
        async.elapse(const Duration(seconds: 1));
        sim.enqueueTarget(b);

        // A velocidad sin límite llegaría casi instantáneo. Con el techo de
        // 20 m/s (con backlog, hasta 32 m/s en el peor caso) necesita al
        // menos ~150/32 ≈ 4.7s — así que a los 3s todavía no debería haber
        // llegado.
        async.elapse(const Duration(seconds: 3));
        final distanciaAB = _mathService.haversineMeters(
          sim.currentPosition!,
          b,
        );
        expect(distanciaAB, greaterThan(1.0));
      });
    });

    test('piso: un tramo lento no deja al marcador caminando a paso de peatón', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 1, 1));
        final sim = ConductorMovementSimulator(now: clock.now);
        addTearDown(sim.dispose);

        const a = LatLng(4.60000, -74.08000);
        // ~30m al este.
        const b = LatLng(4.60000, -74.079730);

        sim.enqueueTarget(a);
        // Gap largo (20s) -> velocidad cruda implícita ~1.5 m/s, bajo
        // cualquier piso razonable.
        async.elapse(const Duration(seconds: 20));
        sim.enqueueTarget(b);

        // Con el piso de 6 m/s, 30m se cubren en 5s como mucho. Dar margen
        // (7s) y confirmar que ya llegó — muy por debajo de los 20s que
        // tomaría a la velocidad cruda sin piso.
        async.elapse(const Duration(seconds: 7));
        final distanciaAB = _mathService.haversineMeters(
          sim.currentPosition!,
          b,
        );
        expect(distanciaAB, lessThan(1.0));
      });
    });
  });

  group('ConductorMovementSimulator — saltos y ruido', () {
    test('salto grande (>200m) se aplica de una vez, sin animar', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 1, 1));
        final sim = ConductorMovementSimulator(now: clock.now);
        addTearDown(sim.dispose);

        const a = LatLng(4.60000, -74.08000);
        // ~300m al este.
        const lejos = LatLng(4.60000, -74.076703);

        sim.enqueueTarget(a);
        async.elapse(const Duration(seconds: 1));
        sim.enqueueTarget(lejos);

        // Sin ningún `elapse` adicional: si fue un snap, ya está ahí.
        expect(sim.currentPosition, lejos);
      });
    });

    test('un ping repetido (misma posición, ej. latido de keepalive) no mueve nada', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2026, 1, 1));
        final sim = ConductorMovementSimulator(now: clock.now);
        addTearDown(sim.dispose);

        const a = LatLng(4.60000, -74.08000);
        // A menos de 1.2m de `a` — mismo caso que reenviar la última
        // posición conocida cuando el conductor está detenido.
        const casiA = LatLng(4.600005, -74.08000);

        sim.enqueueTarget(a);
        async.elapse(const Duration(seconds: 15));
        sim.enqueueTarget(casiA);

        async.elapse(const Duration(seconds: 1));
        expect(sim.currentPosition, a);
      });
    });
  });
}
