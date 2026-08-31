// Cobertura de `segundosRestantesEspera`: la ancla de servidor
// (`solicitudes/{id}.esperaIniciadaEn`) que reemplaza los dos contadores
// locales independientes de cliente y conductor (bug real: el cliente que
// entraba tarde a la pantalla volvía a ver 3:00 aunque al conductor ya le
// quedaran segundos).
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/espera_countdown.dart';

void main() {
  group('segundosRestantesEspera', () {
    test('sin ancla (viaje viejo, o el snapshot con el ancla aún no llegó) '
        'da el total completo', () {
      expect(
        segundosRestantesEspera(inicio: null, ahora: DateTime(2026, 1, 1)),
        180,
      );
    });

    test('a los 168s transcurridos quedan 12 — es el caso real reportado: '
        'el conductor lleva casi los 3 minutos y el cliente entra recién '
        'ahora', () {
      final inicio = DateTime(2026, 1, 1, 12, 0, 0);
      final ahora = inicio.add(const Duration(seconds: 168));
      expect(segundosRestantesEspera(inicio: inicio, ahora: ahora), 12);
    });

    test('pasado el total, se acota a 0 (no negativo)', () {
      final inicio = DateTime(2026, 1, 1, 12, 0, 0);
      final ahora = inicio.add(const Duration(seconds: 400));
      expect(segundosRestantesEspera(inicio: inicio, ahora: ahora), 0);
    });

    test('ancla en el futuro (deriva de reloj entre servidor y cliente) '
        'no da más del total', () {
      final inicio = DateTime(2026, 1, 1, 12, 0, 10);
      final ahora = DateTime(2026, 1, 1, 12, 0, 0);
      expect(segundosRestantesEspera(inicio: inicio, ahora: ahora), 180);
    });

    test('respeta un total distinto al default', () {
      final inicio = DateTime(2026, 1, 1);
      final ahora = inicio.add(const Duration(seconds: 30));
      expect(
        segundosRestantesEspera(inicio: inicio, ahora: ahora, total: 60),
        30,
      );
    });
  });
}
