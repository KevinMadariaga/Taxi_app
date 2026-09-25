import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/dominio/validar_valor_servicio.dart';
import 'package:taxi_app/core/modelos/vehicle_type.dart';

/// Las funciones puras de `dominio/validar_valor_servicio.dart`, con `ahora`
/// inyectable — acá se fija el corte diurno/nocturno y el techo, que antes
/// solo se podían ejercitar a través de `ConfirmarSolicitudViewModel` (eso
/// sigue cubierto, desde el lado del VM, en
/// `validar_valor_servicio_test.dart`).
void main() {
  final dia = DateTime(2026, 9, 19, 12);
  final noche = DateTime(2026, 9, 19, 20);

  group('valorMinimoPermitido', () {
    test('usa la tarifa base diurna entre 06:00 y 18:00', () {
      expect(valorMinimoPermitido(VehicleType.carro, ahora: dia), 7000);
      expect(valorMinimoPermitido(VehicleType.moto, ahora: dia), 3000);
    });

    test('usa la nocturna desde las 18:00 y hasta las 06:00', () {
      expect(valorMinimoPermitido(VehicleType.carro, ahora: noche), 10000);
      expect(valorMinimoPermitido(VehicleType.moto, ahora: noche), 5000);
      expect(
        valorMinimoPermitido(
          VehicleType.carro,
          ahora: DateTime(2026, 9, 19, 5, 59),
        ),
        10000,
      );
    });
  });

  group('valorMaximoPermitido', () {
    test('techoMinimo no deja el techo por debajo del valor vigente', () {
      // Sin ruta trazada el sugerido sale sin el componente por km, y el
      // techo quedaría por debajo de una oferta que el sistema ya aceptó al
      // crear la solicitud (viaje largo en moto). El techo es anti
      // fat-finger, no un recorte retroactivo.
      expect(
        validarValorServicio('70000', tipo: VehicleType.moto, ahora: dia),
        contains('máximo'),
      );
      expect(
        validarValorServicio(
          '70000',
          tipo: VehicleType.moto,
          ahora: dia,
          techoMinimo: 70000,
        ),
        isNull,
      );
    });

    test('es 20x el sugerido y crece con la distancia', () {
      final corto = valorMaximoPermitido(
        VehicleType.carro,
        distanciaKm: 0,
        ahora: dia,
      );
      final largo = valorMaximoPermitido(
        VehicleType.carro,
        distanciaKm: 10,
        ahora: dia,
      );
      expect(corto, 7000 * 20);
      expect(largo, greaterThan(corto));
    });
  });

  group('validarValorServicio', () {
    String? validar(String digits, {VehicleType tipo = VehicleType.carro}) =>
        validarValorServicio(digits, tipo: tipo, distanciaKm: 0, ahora: dia);

    test('rechaza vacío, cero y no numérico', () {
      expect(validar(''), 'Ingresa un valor válido.');
      expect(validar('0'), 'Ingresa un valor válido.');
      expect(validar('abc'), 'Ingresa un valor válido.');
    });

    test('rechaza por debajo del mínimo del vehículo', () {
      expect(validar('1'), contains('mínimo'));
      expect(validar('6999'), contains('carro'));
      expect(validar('2999', tipo: VehicleType.moto), contains('moto'));
      // Lo que para moto es válido, para carro no.
      expect(validar('3000', tipo: VehicleType.moto), isNull);
      expect(validar('3000'), isNotNull);
    });

    test('rechaza por encima del techo anti fat-finger', () {
      expect(validar('140001'), contains('máximo'));
    });

    test('acepta un valor en rango, con o sin separadores', () {
      expect(validar('11000'), isNull);
      expect(validar('11.000'), isNull);
      expect(validar('\$ 11.000'), isNull);
    });

    test('el mismo monto pasa de día y falla de noche', () {
      expect(
        validarValorServicio(
          '7000',
          tipo: VehicleType.carro,
          distanciaKm: 0,
          ahora: dia,
        ),
        isNull,
      );
      expect(
        validarValorServicio(
          '7000',
          tipo: VehicleType.carro,
          distanciaKm: 0,
          ahora: noche,
        ),
        contains('mínimo'),
      );
    });
  });
}
