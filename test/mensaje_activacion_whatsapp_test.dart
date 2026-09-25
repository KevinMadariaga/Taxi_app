import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/activacion_servicio_view.dart';

void main() {
  test('mensaje completo con nombre, celular y vehículo', () {
    final m = mensajeActivacionWhatsapp({
      'nombre': 'Laura',
      'apellido': 'Gómez',
      'telefono': '3001234567',
      'tipoVehiculo': 'carro',
      'modeloVehiculo': 'Chevrolet Spark',
      'colorVehiculo': 'Blanco',
      'placa': 'abc123',
    });
    expect(m, startsWith('Hola, quiero activar el servicio de conductor'));
    expect(m, contains('Soy Laura Gómez y me registré en la app como conductor.'));
    expect(m, contains('Celular: 3001234567'));
    expect(m, contains('Vehículo: Carro Chevrolet Spark Blanco — placa ABC123'));
    expect(m, contains('Adjunto el comprobante'));
  });

  test('sin datos no rompe ni deja huecos', () {
    final m = mensajeActivacionWhatsapp(null);
    expect(m, contains('Soy un conductor registrado'));
    expect(m, isNot(contains('Celular:')));
    expect(m, contains('Vehículo: Carro\n'));
  });
}
