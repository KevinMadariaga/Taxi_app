import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/validators/vehiculo_validator.dart';

void main() {
  test('modelo', () {
    expect(VehiculoValidator.modelo('', tipo: 'carro'), contains('modelo'));
    expect(VehiculoValidator.modelo('Kia', tipo: 'carro'), isNull);
    expect(VehiculoValidator.modelo('Ki', tipo: 'carro'), isNotNull);
  });

  test('color', () {
    expect(VehiculoValidator.color(' ', tipo: 'moto'), contains('moto'));
    expect(VehiculoValidator.color('Azul oscuro', tipo: 'moto'), isNull);
    expect(VehiculoValidator.color('Rojo2', tipo: 'moto'), isNotNull);
  });

  test('descripcion', () {
    expect(
      VehiculoValidator.descripcion('Chevrolet Spark', 'Blanco'),
      'Chevrolet Spark · Blanco',
    );
    expect(VehiculoValidator.descripcion('', 'Blanco'), 'Blanco');
    expect(VehiculoValidator.descripcion(null, null), '');
  });
}
