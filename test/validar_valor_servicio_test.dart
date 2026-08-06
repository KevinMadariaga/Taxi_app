// Regresión: la cadena que fija el valor del servicio no tenía ningún límite.
// `setValorServicio` solo quitaba los no-dígitos, así que `1` y
// `999999999999` se escribían igual en el documento. Un cliente ofertando $1
// spamea a todos los conductores del radio; un cero de más queda persistido.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/viewmodels/confirmar_solicitud_viewmodel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    // El VM construye repositorios reales por defecto (Firestore).
    await setupFirebaseForTests();
  });

  const punto = LocationModel(position: LatLng(8.24, -73.35));

  // El mínimo depende de la franja horaria, así que se lee del propio VM en
  // vez de hardcodear un número que fallaría de noche.
  ConfirmarSolicitudViewModel buildVm(VehicleType tipo) {
    final vm = ConfirmarSolicitudViewModel(
      origenInicial: punto,
      destinoInicial: punto,
    );
    vm.setTipoVehiculo(tipo);
    return vm;
  }

  group('validarValorServicio', () {
    test('rechaza cero y no numéricos', () {
      final vm = buildVm(VehicleType.carro);
      expect(vm.validarValorServicio('0'), isNotNull);
      expect(vm.validarValorServicio(''), isNotNull);
      expect(vm.validarValorServicio('abc'), isNotNull);
    });

    test('rechaza por debajo del mínimo del vehículo', () {
      final vm = buildVm(VehicleType.carro);
      expect(vm.validarValorServicio('1'), isNotNull);
      expect(
        vm.validarValorServicio('${vm.valorMinimoPermitido - 1}'),
        isNotNull,
      );
    });

    test('acepta exactamente el mínimo', () {
      final vm = buildVm(VehicleType.carro);
      expect(vm.validarValorServicio('${vm.valorMinimoPermitido}'), isNull);
    });

    test('rechaza el fat-finger por encima del máximo', () {
      final vm = buildVm(VehicleType.carro);
      expect(vm.validarValorServicio('999999999999'), isNotNull);
      expect(
        vm.validarValorServicio('${vm.valorMaximoPermitido + 1}'),
        isNotNull,
      );
    });

    test('la moto admite un mínimo menor que el carro', () {
      final moto = buildVm(VehicleType.moto);
      final carro = buildVm(VehicleType.carro);
      expect(moto.valorMinimoPermitido, lessThan(carro.valorMinimoPermitido));
      // Un valor válido para moto puede no serlo para carro.
      expect(moto.validarValorServicio('${moto.valorMinimoPermitido}'), isNull);
    });

    test('el mensaje de error explica el límite en pesos', () {
      final vm = buildVm(VehicleType.carro);
      final error = vm.validarValorServicio('1');
      expect(error, contains('mínimo'));
      expect(error, contains('\$'));
    });
  });
}
