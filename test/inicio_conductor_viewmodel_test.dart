// Tests de caracterización de InicioConductorViewmodel — antes de dividirlo
// (ver graphify-out: quedó como la comunidad de cohesión más baja del repo,
// 0.02, tras el refactor de trip_tracking/buscando_taxi).
//
// Alcance: esta clase no tenía NINGÚN punto de inyección
// (FirebaseFirestore.instance/TrackingService()/FirebaseAuth.instance
// hardcodeados como field initializers, sin constructor). Se agregó DI
// mínima (firestore/trackingService/auth/iniciarEscuchaSoporte, mismo patrón
// que BuscandoTaxiViewModel) para habilitar estos tests.
//
// `init()` — el único punto de entrada público que arranca los 4 listeners
// privados (perfil, solicitudes, ratings, assigned-to-me) — SÍ se caracteriza
// acá. Para lograrlo, se arreglaron 2 gaps reales de producción encontrados
// al intentarlo (no solo problemas del test):
// 1. `ErrorReporter.report` llamaba a `FirebaseCrashlytics.instance
//    .recordError(...)` (async) sin manejar su rechazo — cualquier catch en
//    TODO el repo que llamara a ErrorReporter.report podía romper el flujo
//    que ese reporter existe para proteger, si Crashlytics no estaba listo
//    (init temprano de la app, o cualquier entorno de test). Se agregó
//    `.catchError((_) {})`.
// 2. `SoporteNotificationService.instance.iniciarEscuchaUsuario` — un
//    singleton sin ningún punto de inyección que llama a
//    `FirebaseFirestore.instance` REAL (no la fake inyectada) — se
//    inyectó como callback (`iniciarEscuchaSoporte`), default al singleton
//    real, no-op en tests.
//
// `stopBackgroundTrackingService()` sigue tocando el plugin real de
// flutter_background_service (falla con MissingPluginException en este
// entorno) pero ya no rompe el test: con el fix de ErrorReporter, ese fallo
// se registra y se traga como estaba diseñado desde el principio.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/InicioConductorViewModel.dart';

import 'test_helpers/firebase_test_setup.dart';
import 'test_helpers/inicio_conductor_fakes.dart';

const _uid = 'conductor-1';

Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condición no se cumplió dentro de $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

InicioConductorViewmodel _buildVm(FakeFirebaseFirestore firestore) {
  return InicioConductorViewmodel(
    firestore: firestore,
    trackingService: FakeTrackingService(),
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, displayName: 'Juan'),
    ),
    iniciarEscuchaSoporte: (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupFirebaseForTests();
  });

  group('aceptarSolicitud', () {
    late FakeFirebaseFirestore firestore;
    late InicioConductorViewmodel vm;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      vm = _buildVm(firestore);
    });

    tearDown(() => vm.dispose());

    test('lanza si la solicitud no existe', () async {
      await firestore.collection('usuarios').doc(_uid).set({
        'membresia': 'activa',
      });

      expect(
        () => vm.aceptarSolicitud('no-existe'),
        throwsA(isA<StateError>()),
      );
    });

    test('lanza si la membresía no está activa', () async {
      await firestore.collection('usuarios').doc(_uid).set({
        'membresia': 'inactiva',
      });
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
      });

      expect(
        () => vm.aceptarSolicitud('sol-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('lanza si la membresía venció', () async {
      await firestore.collection('usuarios').doc(_uid).set({
        'membresia': 'activa',
        'membresiaVence': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
      });
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
      });

      expect(
        () => vm.aceptarSolicitud('sol-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('lanza si la solicitud ya fue tomada por otro conductor', () async {
      await firestore.collection('usuarios').doc(_uid).set({
        'membresia': 'activa',
      });
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'asignado',
      });

      expect(
        () => vm.aceptarSolicitud('sol-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('éxito: actualiza estado y payload del conductor', () async {
      await firestore.collection('usuarios').doc(_uid).set({
        'membresia': 'activa',
      });
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
      });

      vm.currentLocation = const LatLng(10.0, 10.0);
      await vm.aceptarSolicitud('sol-1');

      final doc = await firestore.collection('solicitudes').doc('sol-1').get();
      final data = doc.data()!;
      expect(data['estado'], 'asignado');
      expect(data['conductor']['id'], _uid);
      expect(data['conductor']['nombre'], vm.displayName);
      expect(data['conductor']['lat'], 10.0);
      expect(data['conductor']['lng'], 10.0);
    });
  });

  group('enviarContraoferta', () {
    late FakeFirebaseFirestore firestore;
    late InicioConductorViewmodel vm;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      vm = _buildVm(firestore);
    });

    tearDown(() => vm.dispose());

    test('lanza si la solicitud ya está asignada', () async {
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'asignado',
      });

      expect(
        () => vm.enviarContraoferta(solicitudId: 'sol-1', nuevoValor: 15000),
        throwsA(isA<StateError>()),
      );
    });

    test('éxito: escribe contraoferta y vuelve a estado buscando', () async {
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
      });

      await vm.enviarContraoferta(solicitudId: 'sol-1', nuevoValor: 15000);

      final doc = await firestore.collection('solicitudes').doc('sol-1').get();
      final data = doc.data()!;
      expect(data['estado'], 'buscando');
      expect(data['estadoContraoferta'], 'pendiente_cliente');
      expect(data['contraofertas'][_uid]['valor'], 15000);
      expect(data['contraofertas'][_uid]['conductor']['id'], _uid);
    });
  });

  group('toggleConductorConnection', () {
    test('alterna disponible en el doc de usuarios', () async {
      final firestore = FakeFirebaseFirestore();
      final vm = _buildVm(firestore);
      addTearDown(vm.dispose);

      await vm.toggleConductorConnection();
      var doc = await firestore.collection('usuarios').doc(_uid).get();
      expect(doc.data()!['disponible'], true);

      await vm.toggleConductorConnection();
      doc = await firestore.collection('usuarios').doc(_uid).get();
      expect(doc.data()!['disponible'], false);
    });
  });

  group('guardarUbicacionConectado', () {
    test('guarda lat/lng en conductores_conectados', () async {
      final firestore = FakeFirebaseFirestore();
      final vm = _buildVm(firestore);
      addTearDown(vm.dispose);

      await vm.guardarUbicacionConectado(const LatLng(11.0, 12.0));

      final doc = await firestore
          .collection('conductores_conectados')
          .doc(_uid)
          .get();
      expect(doc.data()!['ubicacion']['lat'], 11.0);
      expect(doc.data()!['ubicacion']['lng'], 12.0);
    });
  });

  // La posición publicada en `conductores_conectados` se escribía UNA sola
  // vez, al abrir la pantalla, y quedaba congelada toda la sesión. Como el
  // reparto de solicitudes (`onNuevaSolicitudCreada`) decide a quién notificar
  // con ese dato, una posición vieja implica avisar al conductor equivocado.
  group('publicarUbicacionSiCambio', () {
    late FakeFirebaseFirestore firestore;
    late FakeTrackingService tracking;
    late InicioConductorViewmodel vm;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      tracking = FakeTrackingService();
      vm = InicioConductorViewmodel(
        firestore: firestore,
        trackingService: tracking,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _uid, displayName: 'Juan'),
        ),
        iniciarEscuchaSoporte: (_) {},
      );
      addTearDown(vm.dispose);
    });

    Future<Map<String, dynamic>?> leerDoc() async {
      final doc = await firestore
          .collection('conductores_conectados')
          .doc(_uid)
          .get();
      return doc.data();
    }

    test('desconectado no publica nada', () async {
      vm.isConnected = false;
      tracking.position = fakePosition(8.24, -73.35);

      await vm.publicarUbicacionSiCambio();

      expect(await leerDoc(), isNull);
    });

    test('conectado publica la posición actual', () async {
      vm.isConnected = true;
      tracking.position = fakePosition(8.24, -73.35);

      await vm.publicarUbicacionSiCambio();

      final data = await leerDoc();
      expect(data!['ubicacion']['lat'], closeTo(8.24, 1e-9));
      expect(data['ubicacion']['lng'], closeTo(-73.35, 1e-9));
    });

    test('sin GPS disponible no escribe', () async {
      vm.isConnected = true;
      tracking.position = null;

      await vm.publicarUbicacionSiCambio();

      expect(await leerDoc(), isNull);
    });

    test('movimiento menor al umbral no reescribe', () async {
      vm.isConnected = true;
      tracking.position = fakePosition(8.24, -73.35);
      await vm.publicarUbicacionSiCambio();

      // ~11 m: por debajo del umbral de 100 m.
      tracking.position = fakePosition(8.2401, -73.35);
      await vm.publicarUbicacionSiCambio();

      final data = await leerDoc();
      expect(data!['ubicacion']['lat'], closeTo(8.24, 1e-9));
    });

    test('movimiento mayor al umbral sí reescribe', () async {
      vm.isConnected = true;
      tracking.position = fakePosition(8.24, -73.35);
      await vm.publicarUbicacionSiCambio();

      // ~1.1 km: por encima del umbral.
      tracking.position = fakePosition(8.25, -73.35);
      await vm.publicarUbicacionSiCambio();

      final data = await leerDoc();
      expect(data!['ubicacion']['lat'], closeTo(8.25, 1e-9));
    });

    test('desconectarse a mitad de la lectura del GPS aborta la escritura', () async {
      vm.isConnected = true;
      tracking.position = fakePosition(8.24, -73.35);
      // El fake resuelve de forma síncrona-async; se simula la desconexión
      // justo después de pedir la posición.
      final future = vm.publicarUbicacionSiCambio();
      vm.isConnected = false;
      await future;

      expect(await leerDoc(), isNull);
    });
  });

  group('Preview y ruta (estado puro)', () {
    late InicioConductorViewmodel vm;

    setUp(() {
      vm = _buildVm(FakeFirebaseFirestore());
    });

    tearDown(() => vm.dispose());

    test('setRoute agrega puntos y polyline', () {
      vm.setRoute('sol-1', const [LatLng(0, 0), LatLng(1, 1)]);
      expect(vm.routePoints['sol-1'], hasLength(2));
      expect(
        vm.routePolylines.any((p) => p.polylineId.value == 'route_sol-1'),
        true,
      );
    });

    test('clearPreviewAndRoutes resetea todo el estado de preview', () {
      vm.setRoute('sol-1', const [LatLng(0, 0), LatLng(1, 1)]);
      vm.setMapExpanded(true);

      vm.clearPreviewAndRoutes();

      expect(vm.selectedPreview, isNull);
      expect(vm.isMapExpanded, false);
      expect(vm.routePoints, isEmpty);
      expect(
        vm.routePolylines.any((p) => p.polylineId.value == 'route_sol-1'),
        false,
      );
    });

    test('calculateBearing: hacia el este da ~90°, hacia el norte da ~0°', () {
      final east = vm.calculateBearing(
        const LatLng(0, 0),
        const LatLng(0, 1),
      );
      final north = vm.calculateBearing(
        const LatLng(0, 0),
        const LatLng(1, 0),
      );
      expect(east, closeTo(90, 1));
      expect(north, closeTo(0, 1));
    });
  });

  group('Lista de solicitudes (vía ensureSolicitudesSubscription, sin init())', () {
    late FakeFirebaseFirestore firestore;
    late InicioConductorViewmodel vm;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      vm = _buildVm(firestore);
    });

    tearDown(() => vm.dispose());

    Future<void> seedSolicitud(
      String id, {
      required double lat,
      required double lng,
      String estado = 'buscando',
      String? tipoVehiculo,
    }) {
      return firestore.collection('solicitudes').doc(id).set({
        'estado': estado,
        'cliente': {
          'id': 'cliente-$id',
          'nombre': 'Cliente $id',
          'ubicacion': {'lat': lat, 'lng': lng},
        },
        if (tipoVehiculo != null) 'tipoVehiculo': tipoVehiculo,
      });
    }

    test('no suscribe si isConnected es false', () async {
      await seedSolicitud('sol-1', lat: 10.0001, lng: 10.0001);
      vm.isConnected = false;

      vm.ensureSolicitudesSubscription();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.solicitudes, isEmpty);
    });

    test('excluye solicitudes a más de 3km', () async {
      vm.currentLocation = const LatLng(10.0, 10.0);
      // ~1.1km al norte
      await seedSolicitud('cerca', lat: 10.01, lng: 10.0);
      // ~11km al norte, fuera de rango
      await seedSolicitud('lejos', lat: 10.1, lng: 10.0);

      vm.isConnected = true;
      vm.ensureSolicitudesSubscription();
      await _pumpUntil(() => vm.solicitudes.isNotEmpty);
      // Deja asentar el snapshot completo (ambos docs en un solo evento).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.solicitudes.map((s) => s.id), ['cerca']);
    });

    test('excluye solicitudes de otro tipo de vehículo', () async {
      vm.currentLocation = const LatLng(10.0, 10.0);
      vm.tipoVehiculoConductor = 'carro';
      await seedSolicitud('moto', lat: 10.001, lng: 10.0, tipoVehiculo: 'moto');
      await seedSolicitud(
        'carro',
        lat: 10.001,
        lng: 10.0,
        tipoVehiculo: 'carro',
      );

      vm.isConnected = true;
      vm.ensureSolicitudesSubscription();
      await _pumpUntil(() => vm.solicitudes.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.solicitudes.map((s) => s.id), ['carro']);
    });

    test('ordena por distancia ascendente', () async {
      vm.currentLocation = const LatLng(10.0, 10.0);
      await seedSolicitud('lejana', lat: 10.02, lng: 10.0);
      await seedSolicitud('cercana', lat: 10.005, lng: 10.0);

      vm.isConnected = true;
      vm.ensureSolicitudesSubscription();
      await _pumpUntil(() => vm.solicitudes.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.solicitudes.map((s) => s.id).toList(), [
        'cercana',
        'lejana',
      ]);
    });
  });

  group('init() — perfil (valida el fix de duplicación)', () {
    test('hidrata displayName/plate/foto/rating y se actualiza en vivo', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({
        'nombre': 'Carlos Pérez',
        'placa': 'ABC123',
        'foto': 'http://foto1',
        'calificacionPromedio': 4.5,
        'totalCalificaciones': 10,
      });
      final vm = _buildVm(firestore);

      await vm.init();
      await _pumpUntil(() => vm.displayName == 'Carlos Pérez');

      expect(vm.plate, 'ABC123');
      expect(vm.photoUrl, 'http://foto1');
      expect(vm.rating, 4.5);
      expect(vm.totalRatings, 10);

      // Actualización en vivo: pasa por _subscribeConductorStatus, el OTRO
      // call site que ahora comparte _hydrateProfileFromConductorDoc con
      // _loadProfile — si hubiera vuelto a divergir, este assert lo agarra.
      await firestore.collection('usuarios').doc(_uid).update({
        'nombre': 'Carlos Actualizado',
        'placa': 'XYZ999',
      });
      await _pumpUntil(() => vm.displayName == 'Carlos Actualizado');
      expect(vm.plate, 'XYZ999');

      vm.dispose();
    });
  });

  group('init() — conexión online/offline', () {
    test('disponible=true activa isConnected y arranca la lista de solicitudes', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({
        'disponible': false,
      });
      final vm = _buildVm(firestore);
      vm.currentLocation = const LatLng(10.0, 10.0);

      await vm.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.isConnected, false);

      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
        'cliente': {
          'id': 'cliente-1',
          'nombre': 'Cliente',
          'ubicacion': {'lat': 10.001, 'lng': 10.0},
        },
      });
      await firestore.collection('usuarios').doc(_uid).update({
        'disponible': true,
      });

      await _pumpUntil(() => vm.isConnected);
      await _pumpUntil(() => vm.solicitudes.isNotEmpty);
      expect(vm.solicitudes.single.id, 'sol-1');

      vm.dispose();
    });

    test('desconectar limpia solicitudes/preview y detiene el listener', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({
        'disponible': true,
      });
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'buscando',
        'cliente': {
          'id': 'cliente-1',
          'nombre': 'Cliente',
          'ubicacion': {'lat': 10.001, 'lng': 10.0},
        },
      });
      final vm = _buildVm(firestore);
      vm.currentLocation = const LatLng(10.0, 10.0);

      await vm.init();
      await _pumpUntil(() => vm.solicitudes.isNotEmpty);

      await firestore.collection('usuarios').doc(_uid).update({
        'disponible': false,
      });
      await _pumpUntil(() => !vm.isConnected);

      expect(vm.solicitudes, isEmpty);
      expect(vm.selectedPreview, isNull);

      vm.dispose();
    });
  });

  group('init() — ratings agregados de solicitudes completadas', () {
    test('promedia calificaciones de solicitudes completado', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({});
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'completado',
        'conductor': {'id': _uid},
        'tarifa': {'total': 20000},
        'calificacion': {'score': 5},
      });
      await firestore.collection('solicitudes').doc('sol-2').set({
        'estado': 'completado',
        'conductor': {'id': _uid},
        'tarifa': {'total': 10000},
        'calificacion': {'score': 3},
      });
      // No cuenta: no está completado.
      await firestore.collection('solicitudes').doc('sol-3').set({
        'estado': 'buscando',
        'conductor': {'id': _uid},
      });

      final vm = _buildVm(firestore);
      await vm.init();

      await _pumpUntil(() => vm.totalCompletedTrips == 2);
      expect(vm.totalServiceValue, 30000);
      expect(vm.totalRatings, 2);
      expect(vm.rating, closeTo(4.0, 0.01));

      vm.dispose();
    });
  });

  group('init() — asignado a mí', () {
    test('dispara onAsignadoAMi una sola vez cuando una solicitud pasa a asignado', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('usuarios').doc(_uid).set({});
      final vm = _buildVm(firestore);

      final asignadas = <String>[];
      vm.onAsignadoAMi = asignadas.add;

      await vm.init();

      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': 'asignado',
        'conductor': {'id': _uid},
      });

      await _pumpUntil(() => asignadas.isNotEmpty);
      expect(asignadas, ['sol-1']);

      // Un segundo evento sobre la misma solicitud (p. ej. otro campo
      // actualizado) no debe volver a dispararlo.
      await firestore.collection('solicitudes').doc('sol-1').update({
        'updatedAt': Timestamp.now(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(asignadas, ['sol-1']);

      vm.dispose();
    });
  });

  // Regresión: `listenPreviewSolicitudStatus` llamaba a `onAsignado()` con
  // solo mirar `estado == asignado`, sin comprobar de quién era el viaje. Todo
  // conductor con la preview abierta era navegado al viaje que ganó otro.
  group('listenPreviewSolicitudStatus — dueño del viaje', () {
    late FakeFirebaseFirestore firestore;
    late InicioConductorViewmodel vm;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      vm = _buildVm(firestore);
      await firestore.collection('solicitudes').doc('sol-1').set({
        'estado': SolicitudEstado.buscando,
        'cliente': {'id': 'cli-1'},
      });
    });

    tearDown(() => vm.dispose());

    /// Engancha el listener y devuelve (asignados, liberados).
    Future<(List<int>, List<int>)> escuchar() async {
      final asignado = <int>[];
      final liberado = <int>[];
      await vm.listenPreviewSolicitudStatus(
        solicitudId: 'sol-1',
        onAsignado: () async => asignado.add(1),
        onCanceladoOrRemoved: () async => liberado.add(1),
      );
      return (asignado, liberado);
    }

    test('asignado a MÍ navega al viaje', () async {
      final (asignado, liberado) = await escuchar();

      await firestore.collection('solicitudes').doc('sol-1').update({
        'estado': SolicitudEstado.asignado,
        'conductor': {'id': _uid},
      });

      await _pumpUntil(() => asignado.isNotEmpty);
      expect(liberado, isEmpty);
    });

    test('asignado a OTRO conductor libera la preview, no navega', () async {
      final (asignado, liberado) = await escuchar();

      await firestore.collection('solicitudes').doc('sol-1').update({
        'estado': SolicitudEstado.asignado,
        'conductor': {'id': 'otro-conductor'},
      });

      await _pumpUntil(() => liberado.isNotEmpty);
      expect(asignado, isEmpty);
    });

    test('asignado sin campo conductor libera la preview', () async {
      final (asignado, liberado) = await escuchar();

      await firestore.collection('solicitudes').doc('sol-1').update({
        'estado': SolicitudEstado.asignado,
      });

      await _pumpUntil(() => liberado.isNotEmpty);
      expect(asignado, isEmpty);
    });

    // Estados de sesión ya en curso o terminales: la solicitud dejó de estar
    // disponible para este conductor, nunca debe arrastrarlo a la pantalla.
    for (final estado in [
      SolicitudEstado.enCamino,
      SolicitudEstado.enRuta,
      SolicitudEstado.completado,
      SolicitudEstado.sinRespuesta,
    ]) {
      test('estado "$estado" de otro conductor libera la preview', () async {
        final (asignado, liberado) = await escuchar();

        await firestore.collection('solicitudes').doc('sol-1').update({
          'estado': estado,
          'conductor': {'id': 'otro-conductor'},
        });

        await _pumpUntil(() => liberado.isNotEmpty);
        expect(asignado, isEmpty);
      });
    }

    test('cancelado libera la preview', () async {
      final (asignado, liberado) = await escuchar();

      await firestore.collection('solicitudes').doc('sol-1').update({
        'estado': SolicitudEstado.cancelado,
      });

      await _pumpUntil(() => liberado.isNotEmpty);
      expect(asignado, isEmpty);
    });
  });
}
