import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/data/models/solicitud_item.dart';
import 'package:taxi_app/features/resumen_viaje/models/resumen_viaje_model.dart';

void main() {
  group('Modelos de datos', () {
    test('SolicitudItem puede instanciarse', () {
      // GeoPoint requiere valores dummy
      final model = SolicitudItem(
        id: '1',
        clienteId: 'cliente',
        ubicacionInicial: const GeoPoint(0, 0),
      );
      expect(model, isNotNull);
    });

    test('ResumenViajeModel usa tarifa.total como valor del servicio', () {
      final model = ResumenViajeModel.fromFirestore(
        solicitudId: 'sol_1',
        data: {
          'tarifa': {'total': 18500},
          'valorServicio': 9999,
          'destino': {'direccion': 'Centro'},
        },
      );

      expect(model.valorServicio, 18500);
    });

    test('ResumenViajeModel mantiene fallback de valorServicio', () {
      final model = ResumenViajeModel.fromFirestore(
        solicitudId: 'sol_2',
        data: {
          'valorServicio': 24000,
          'destino': {'direccion': 'Terminal'},
        },
      );

      expect(model.valorServicio, 24000);
    });
  });
}
