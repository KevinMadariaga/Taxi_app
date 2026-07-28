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
}
