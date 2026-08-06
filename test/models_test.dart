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

  // Regresión: `fromMap` leía el campo legacy `contraoferta`, que guarda la
  // ÚLTIMA oferta de cualquier conductor. La preview lo pinta como "Tu
  // contraoferta", así que el conductor A veía la oferta de B como propia.
  group('SolicitudItem — contraoferta propia vs ajena', () {
    Map<String, dynamic> docConOfertas() => {
      'estado': 'buscando',
      'cliente': {'id': 'cli-1'},
      'tarifa': {'total': 10000},
      // Legacy: la última oferta escrita, la de B.
      'contraoferta': {'estado': 'pendiente_cliente', 'valor': 15000},
      'contraofertas': {
        'conductor-A': {'estado': 'pendiente_cliente', 'valor': 12000},
        'conductor-B': {'estado': 'pendiente_cliente', 'valor': 15000},
      },
    };

    test('lee la oferta del conductor que mira, no la legacy', () {
      final a = SolicitudItem.fromMap(
        's1',
        docConOfertas(),
        conductorUid: 'conductor-A',
      );
      expect(a.valorContraoferta, 12000);

      final b = SolicitudItem.fromMap(
        's1',
        docConOfertas(),
        conductorUid: 'conductor-B',
      );
      expect(b.valorContraoferta, 15000);
    });

    test('conductor sin oferta propia no ve ninguna contraoferta', () {
      final c = SolicitudItem.fromMap(
        's1',
        docConOfertas(),
        conductorUid: 'conductor-C',
      );
      expect(c.valorContraoferta, isNull);
      // Tampoco debe filtrarse por el `estadoContraoferta` global.
      expect(c.estadoContraoferta, isNull);
    });

    test('estadoContraoferta global no se usa cuando se sabe quién mira', () {
      final doc = docConOfertas()..['estadoContraoferta'] = 'pendiente_cliente';
      final c = SolicitudItem.fromMap('s1', doc, conductorUid: 'conductor-C');
      expect(c.estadoContraoferta, isNull);
    });

    test('sin conductorUid mantiene el comportamiento legacy', () {
      final legacy = SolicitudItem.fromMap('s1', docConOfertas());
      expect(legacy.valorContraoferta, 15000);
    });

    test('oferta propia retirada por el cliente deja de verse', () {
      final doc = docConOfertas();
      // El cliente rechazó a A: su entrada se borra del mapa, pero el campo
      // legacy sigue teniendo un valor.
      (doc['contraofertas'] as Map).remove('conductor-A');

      final a = SolicitudItem.fromMap(
        's1',
        doc,
        conductorUid: 'conductor-A',
      );
      expect(a.valorContraoferta, isNull);
    });
  });
}
