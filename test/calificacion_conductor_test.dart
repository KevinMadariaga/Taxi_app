import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/utils/calificacion_conductor.dart';

void main() {
  test('prioriza el promedio consolidado de usuarios/{uid}', () {
    final c = resolverCalificacionConductor(
      {'calificacionConductor': 4.6, 'totalCalificaciones': 10},
      [
        {'calificacion': 1},
      ],
    );
    expect(c.promedio, 4.6);
    expect(c.total, 10);
  });

  test('sin consolidado, promedia la calificación de los viajes', () {
    final c = resolverCalificacionConductor(
      {'calificacionPromedio': 0, 'totalCalificaciones': 0},
      [
        {'calificacion': 5},
        {
          'calificacion': {'score': 4},
        },
        {'estado': 'completado'},
      ],
    );
    expect(c.promedio, 4.5);
    expect(c.total, 2);
  });

  test('sin nada: total 0', () {
    expect(resolverCalificacionConductor(null, const []).total, 0);
  });
}
