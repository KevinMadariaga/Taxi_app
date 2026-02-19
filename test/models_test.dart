import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/data/models/registro_cliente_model.dart';
import 'package:taxi_app/data/models/solicitud_id.dart';
import 'package:taxi_app/data/models/viewmodels/registro_cliente_viewmodel.dart';

void main() {
  group('Modelos de datos', () {
    test('RegistroClienteModel puede instanciarse', () {
      final model = RegistroClienteModel(
        nombre: 'Test',
        telefono: '123456789',
        correo: 'test@email.com',
        password: '123456',
      );
      expect(model, isNotNull);
    });
    test('SolicitudItem puede instanciarse', () {
      // GeoPoint requiere valores dummy
      final model = SolicitudItem(
        id: '1',
        clienteId: 'cliente',
        ubicacionInicial: const GeoPoint(0, 0),
      );
      expect(model, isNotNull);
    });
    test('RegistroClienteViewModel puede instanciarse', () {
      final model = RegistroClienteViewModel();
      expect(model, isNotNull);
    });
  });
}
