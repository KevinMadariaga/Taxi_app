import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/comentarios_conductor_viewmodel.dart';

DriverCommentItem c(double estrellas) => DriverCommentItem(
  comment: 'ok',
  createdAt: DateTime(2026, 9, 1),
  estrellas: estrellas,
);

void main() {
  test('resumen promedia solo los que tienen estrellas', () {
    final r = resumenComentarios([c(5), c(4), c(0)]);
    expect(r.total, 3);
    expect(r.promedio, 4.5);
  });

  test('resumen vacío', () {
    final r = resumenComentarios(const []);
    expect(r.total, 0);
    expect(r.promedio, 0);
  });
}
