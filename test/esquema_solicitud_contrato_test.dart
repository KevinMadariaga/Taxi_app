// Contrato del documento `solicitudes`.
//
// Hay UN solo sitio que crea el documento (`SolicitudRepositoryImpl.crear`) y
// tres lectores independientes que lo interpretan: la lista del conductor
// (`SolicitudItem`), el seguimiento del cliente (`SolicitudModel`) y las
// pantallas de viaje (`ViajeModel`). Cada uno resuelve los mismos datos por su
// cuenta, probando varias claves alternativas.
//
// La auditoría encontró siete inconsistencias en ese esquema (origen escrito
// tres veces en tres tipos, `origen` y `destino` con claves distintas para lo
// mismo, precio en cuatro campos, `distanciaKm` leído pero nunca escrito…).
// Ninguna rompe hoy porque los lectores son tolerantes, pero cualquier cambio
// en el escritor puede dejar a uno de ellos con `null` sin que nada avise.
//
// Este test hace el round-trip completo —escribir de verdad y leer con los
// tres modelos— para que esa clase de regresión falle acá y no en producción.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/confirmar_solicitud/datos/repositorios/solicitud_repository_impl.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/dominio/entidades/cliente_actual.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/modelos/viaje_model.dart';
import 'package:taxi_app/core/constants/estado_contraoferta.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/data/models/solicitud_item.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/solicitud_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SolicitudRepositoryImpl repo;

  const origen = LocationModel(position: LatLng(8.2400, -73.3500));
  const destino = LocationModel(position: LatLng(8.2500, -73.3600));
  const cliente = ClienteActual(
    id: 'cli-1',
    nombre: 'Kevin',
    fotoUrl: 'https://example.com/foto.jpg',
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SolicitudRepositoryImpl(firestore: firestore);
  });

  Future<DocumentSnapshot<Map<String, dynamic>>> crearYLeer({
    String comentario = 'Portón blanco',
    VehicleType tipo = VehicleType.carro,
    double valor = 12000,
  }) async {
    final id = await repo.crear(
      cliente: cliente,
      origen: origen,
      origenDireccion: 'Carrera 7 #21-100',
      destino: destino,
      destinoDireccion: 'Terminal de transportes',
      tipoVehiculo: tipo,
      metodoPago: 'Efectivo',
      comentario: comentario,
      valorServicio: valor,
    );
    return firestore.collection('solicitudes').doc(id).get();
  }

  group('escritura', () {
    test('nace en buscando y sin contraoferta', () async {
      final doc = await crearYLeer();
      final data = doc.data()!;

      // Las reglas de Firestore exigen exactamente este estado al crear.
      expect(data['estado'], SolicitudEstado.buscando);
      expect(data['estadoContraoferta'], EstadoContraoferta.sinContraoferta);
      expect(
        (data['contraoferta'] as Map)['estado'],
        EstadoContraoferta.sinContraoferta,
      );
    });

    test('el estado escrito es el que consulta la lista del conductor', () async {
      final doc = await crearYLeer();
      // `PendingSolicitudesController` filtra con `whereIn [buscando, pending,
      // pendiente]`: si el escritor cambiara el literal, el conductor dejaría
      // de ver las solicitudes sin ningún error visible.
      expect(
        ['buscando', 'pending', 'pendiente'],
        contains(data(doc)['estado']),
      );
    });

    test('el origen se escribe en las tres formas que esperan los lectores', () async {
      final d = data(await crearYLeer());

      // Denormalización conocida (riesgo #5 del CLAUDE.md): tres copias del
      // mismo punto, en tres formas distintas. Se fija para que quien las
      // consolide vea aquí qué lectores dependen de cada una.
      expect(d['cliente']['ubicacion']['lat'], origen.position.latitude);
      expect(d['origen']['lat'], origen.position.latitude);
      expect(d['ubicacion_inicial'], isA<GeoPoint>());
      expect(
        (d['ubicacion_inicial'] as GeoPoint).latitude,
        origen.position.latitude,
      );
    });

    test('origen y destino usan claves distintas para la dirección', () async {
      final d = data(await crearYLeer());

      // `origen` trae address/title y NO direccion; `destino` al revés.
      expect(d['origen'].containsKey('address'), isTrue);
      expect(d['origen'].containsKey('title'), isTrue);
      expect(d['origen'].containsKey('direccion'), isFalse);

      expect(d['destino'].containsKey('direccion'), isTrue);
      expect(d['destino'].containsKey('address'), isFalse);
      expect(d['destino'].containsKey('title'), isFalse);
    });

    test('el precio queda en tarifa.total, que es lo que todos leen primero', () async {
      final d = data(await crearYLeer(valor: 12000));
      expect(d['tarifa']['total'], 12000);
      expect(d['tarifa']['propuestaCliente'], 12000);
      expect(d['valorServicioPropuesto'], 12000);
    });

    test('distanciaKm NO se escribe (el conductor la recalcula)', () async {
      final d = data(await crearYLeer());
      expect(d.containsKey('distanciaKm'), isFalse);
    });

    test('conductor no se inicializa; las reglas lo leen a la defensiva', () async {
      final d = data(await crearYLeer());
      expect(d.containsKey('conductor'), isFalse);
    });
  });

  group('lectura: los tres modelos interpretan el mismo documento', () {
    test('SolicitudItem (lista del conductor)', () async {
      final doc = await crearYLeer();
      final item = SolicitudItem.fromMap(doc.id, doc.data()!);

      expect(item.clienteId, 'cli-1');
      expect(item.nombreCliente, 'Kevin');
      expect(item.valorServicio, 12000);
      expect(item.metodoPago, 'Efectivo');
      expect(item.comentarioCliente, 'Portón blanco');
      expect(item.tipoVehiculo, 'carro');
      expect(item.ubicacionInicial.latitude, origen.position.latitude);
      // Resuelve el destino por `direccion` porque `title`/`address` no se
      // escriben en ese mapa.
      expect(item.destinoTitle, 'Terminal de transportes');
      // Nunca escrito: se calcula en el dispositivo del conductor.
      expect(item.distanciaKm, isNull);
      expect(item.valorContraoferta, isNull);
    });

    test('SolicitudModel (seguimiento del cliente)', () async {
      final doc = await crearYLeer();
      final model = SolicitudModel.fromFirestore(doc);

      expect(model.estado, SolicitudEstado.buscando);
      expect(model.valorServicio, 12000);
      expect(model.metodoPago, 'Efectivo');
      expect(model.destinoDireccion, 'Terminal de transportes');
    });

    test('ViajeModel (pantallas de viaje)', () async {
      final doc = await crearYLeer();
      final viaje = ViajeModel.fromSnapshot(doc);

      expect(viaje.estado, SolicitudEstado.buscando);
      expect(viaje.valorServicio, 12000);
      expect(viaje.cliente.ubicacion?.latitude, origen.position.latitude);
      expect(viaje.destino.ubicacion?.latitude, destino.position.latitude);
    });

    test('los tres coinciden en el precio', () async {
      final doc = await crearYLeer(valor: 9500);

      expect(SolicitudItem.fromMap(doc.id, doc.data()!).valorServicio, 9500);
      expect(SolicitudModel.fromFirestore(doc).valorServicio, 9500);
      expect(ViajeModel.fromSnapshot(doc).valorServicio, 9500);
    });

    test('los tres coinciden en el punto de recogida', () async {
      final doc = await crearYLeer();
      final esperado = origen.position.latitude;

      expect(
        SolicitudItem.fromMap(doc.id, doc.data()!).ubicacionInicial.latitude,
        esperado,
      );
      expect(
        ViajeModel.fromSnapshot(doc).cliente.ubicacion?.latitude,
        esperado,
      );
    });
  });

  group('moto', () {
    test('el tipo se guarda con la clave que filtra el conductor', () async {
      final doc = await crearYLeer(tipo: VehicleType.moto);
      expect(doc.data()!['tipoVehiculo'], 'moto');
      // `PendingSolicitudesController` compara en minúsculas contra el tipo
      // del conductor, y `ViajeModel` deriva `isMoto` de este mismo campo.
      expect(ViajeModel.fromSnapshot(doc).isMoto, isTrue);
    });
  });

  group('comentario', () {
    test('vacío no rompe a ningún lector', () async {
      final doc = await crearYLeer(comentario: '');
      expect(doc.data()!['comentario'], '');
      // El conductor lo normaliza a null para no pintar una tarjeta vacía.
      expect(SolicitudItem.fromMap(doc.id, doc.data()!).comentarioCliente, isNull);
    });
  });
}

Map<String, dynamic> data(DocumentSnapshot<Map<String, dynamic>> doc) =>
    doc.data()!;
