// Tests de caracterización de TripTrackingViewModel (paso 1 del plan de
// refactor: ver graphify-out — comunidad "Features Trip Tracking Cliente
// Viewmodels" tiene la cohesión más baja del repo, 0.02).
//
// Objetivo: fijar el comportamiento HOY del motor de animación/smoothing del
// marcador del conductor y del recálculo de ruta, antes de extraerlo a
// colaboradores separados. Esta zona tiene historial de incidentes reales
// documentados en los comentarios del propio archivo (ANR por saturar el
// hilo principal, pantalla negra del mapa nativo al volver de background) —
// por eso se prioriza sobre el resto del viewmodel.
//
// Fuera de alcance deliberado en esta tanda:
// - Chat (sendMessage/markChatAsRead/notificaciones de mensaje): no tiene
//   historial de incidentes, se deja para una tanda de tests separada.
// - Conectividad offline/reconexión: se mockea siempre "online" para que
//   `init()` no falle; el comportamiento offline no se caracteriza aquí.
// - Notificación de proximidad (`_checkProximityNotification`): no está
//   protegida por try/catch en el código real, así que todos los escenarios
//   mantienen cliente/conductor a >70m de distancia para no dispararla contra
//   el plugin real de notificaciones (no mockeado en esta tanda).
//
// Nota sobre `fake_async`: se evaluó usarlo para controlar el Timer de 50ms
// de `_tickMovement` sin esperas reales, pero el código lee tiempo real vía
// `DateTime.now()` (no `package:clock`), que `fake_async` NO intercepta. Usar
// `fake_async` aquí habría dejado el throttle de 200/400ms y el cálculo de
// velocidad basado en tiempo real completamente rotos en los tests (el reloj
// fake no avanza esas lecturas). Se optó por Timers reales + polling con
// `_pumpUntil`, tolerante a jitter del scheduler, a costa de ~10-20s reales
// de suite.

import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/solicitud_model.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/usuario_model.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/local_cache_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/viewmodels/trip_tracking_viewmodel.dart';

import 'test_helpers/trip_tracking_fakes.dart';

const _earthRadius = 6371000.0;
const _clienteId = 'cliente-1';
const _conductorId = 'conductor-1';
const _solicitudId = 'sol-1';

/// Offsetea `origin` por metros norte/este (aprox., válido para distancias
/// cortas) usando el mismo modelo esférico que `MapService.distanceMeters`.
LatLng _offsetMeters(
  LatLng origin, {
  double northMeters = 0,
  double eastMeters = 0,
}) {
  final dLat = northMeters / _earthRadius * (180 / math.pi);
  final dLng =
      eastMeters /
      (_earthRadius * math.cos(origin.latitude * math.pi / 180)) *
      (180 / math.pi);
  return LatLng(origin.latitude + dLat, origin.longitude + dLng);
}

double _distanceMeters(LatLng a, LatLng b) {
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return _earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

UsuarioModel _usuario({
  required String id,
  LatLng? posicion,
  String direccion = '',
}) {
  return UsuarioModel(
    id: id,
    nombre: 'Nombre $id',
    fotoUrl: '',
    fotoVehiculoUrl: '',
    placaVehiculo: '',
    lat: posicion?.latitude,
    lng: posicion?.longitude,
    direccion: direccion,
  );
}

SolicitudModel _solicitud({
  required LatLng cliente,
  LatLng? conductor,
  String estado = 'en_camino',
}) {
  return SolicitudModel(
    id: _solicitudId,
    estado: estado,
    // direccion no vacía: evita que el viewmodel dispare geocoding inverso
    // real (`_resolverDireccionCliente`) contra el plugin `geocoding`.
    cliente: _usuario(id: _clienteId, posicion: cliente, direccion: 'Calle Falsa 123'),
    conductor: _usuario(id: _conductorId, posicion: conductor),
    updatedAt: DateTime.now(),
  );
}

/// Sondea `condition` hasta que sea true o expire `timeout`. Más robusto que
/// un `Future.delayed` fijo frente al jitter del Timer real de 50ms.
Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condición no se cumplió dentro de $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ConnectivityPlatform.instance = FakeConnectivityPlatform();

  // Cliente fijo; conductor arranca ~500m al norte (bien por encima del
  // umbral de 70m de la notificación de proximidad en todo momento).
  final clientePos = const LatLng(10.0, 10.0);
  final conductorInicial = _offsetMeters(clientePos, northMeters: 500);

  late StreamController<SolicitudModel> solicitudController;
  late FakeTripTrackingFirebaseService firebaseService;
  late FakeMapService mapService;
  late FakeChatService chatService;
  late TripTrackingViewModel vm;

  Future<void> setUpViewModel() async {
    SharedPreferences.setMockInitialValues({});
    solicitudController = StreamController<SolicitudModel>.broadcast();
    firebaseService = FakeTripTrackingFirebaseService(solicitudController.stream);
    mapService = FakeMapService();
    chatService = FakeChatService();

    vm = TripTrackingViewModel(
      solicitudId: _solicitudId,
      currentUserId: _clienteId,
      cancelledBy: _clienteId,
      firebaseService: firebaseService,
      mapService: mapService,
      chatService: chatService,
      localCacheService: LocalCacheService(),
    );
    await vm.init();
  }

  Future<void> emitirYEsperar(SolicitudModel solicitud) async {
    solicitudController.add(solicitud);
    await _pumpUntil(() => vm.solicitud?.updatedAt == solicitud.updatedAt);
  }

  tearDown(() async {
    vm.dispose();
    await solicitudController.close();
  });

  group('Primera posición del conductor', () {
    setUp(setUpViewModel);

    test('se aplica de inmediato, sin animación (snap directo)', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));

      expect(vm.conductorPositionNotifier.value, conductorInicial);
      expect(mapService.fetchCount, 1);
    });
  });

  group('Movimiento pequeño del conductor (crawl)', () {
    setUp(setUpViewModel);

    test('anima gradualmente hacia el nuevo punto, no salta instantáneo', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));

      final siguiente = _offsetMeters(conductorInicial, northMeters: -15);
      solicitudController.add(
        _solicitud(cliente: clientePos, conductor: siguiente),
      );

      // Justo tras la emisión (antes de que corran ticks del Timer de 50ms),
      // la posición mostrada todavía debe ser la vieja: la interpolación pasa
      // por el motor de movimiento, no por un salto directo al dato crudo.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(vm.conductorPositionNotifier.value, conductorInicial);

      // Con tiempo suficiente para varios ticks, debe converger al punto
      // nuevo (dentro de un margen chico).
      await _pumpUntil(
        () =>
            _distanceMeters(vm.conductorPositionNotifier.value!, siguiente) < 1.5,
      );
    });
  });

  group('Salto grande del conductor (>200m)', () {
    setUp(setUpViewModel);

    test('se aplica de una vez, sin animar el crawl (evita el ANR documentado)', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));

      final salto = _offsetMeters(conductorInicial, northMeters: -300);
      solicitudController.add(_solicitud(cliente: clientePos, conductor: salto));

      // Snap: no requiere esperar ticks del Timer, es sincrónico dentro del
      // listener del stream.
      await _pumpUntil(
        () => vm.conductorPositionNotifier.value == salto,
        timeout: const Duration(milliseconds: 500),
      );
    });
  });

  group('Pausa/resume en background', () {
    setUp(setUpViewModel);

    test('pausa detiene el timer; resume aplica snap a la posición real (no reanuda el crawl viejo)', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));

      final destinoCrawl = _offsetMeters(conductorInicial, northMeters: -15);
      solicitudController.add(
        _solicitud(cliente: clientePos, conductor: destinoCrawl),
      );

      // Deja que el crawl arranque (al menos un tick) pero no converja.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      vm.pauseForBackground();
      final posAlPausar = vm.conductorPositionNotifier.value;

      // Mientras está en background, la posición no debe moverse más.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(vm.conductorPositionNotifier.value, posAlPausar);

      vm.resumeFromBackground();

      // Al resumir: snap directo a la última posición cruda conocida, no
      // continúa el crawl viejo desde `posAlPausar`.
      await _pumpUntil(
        () => vm.conductorPositionNotifier.value == destinoCrawl,
        timeout: const Duration(milliseconds: 500),
      );
    });
  });

  group('Recálculo de ruta', () {
    setUp(setUpViewModel);

    test('se calcula una sola vez; movimientos chicos sin desvío no la recalculan', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));
      expect(mapService.fetchCount, 1);

      final cercano = _offsetMeters(conductorInicial, northMeters: -10);
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: cercano));

      expect(mapService.fetchCount, 1);
    });

    test('desvío >40m de la ruta fuerza recálculo; un segundo desvío inmediato lo bloquea por cooldown', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));
      expect(mapService.fetchCount, 1);

      final desviado = _offsetMeters(
        conductorInicial,
        northMeters: -10,
        eastMeters: 65,
      );
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: desviado));
      expect(mapService.fetchCount, 2);

      final desviadoOtraVez = _offsetMeters(
        desviado,
        northMeters: -10,
        eastMeters: 65,
      );
      await emitirYEsperar(
        _solicitud(cliente: clientePos, conductor: desviadoOtraVez),
      );

      // Cooldown de 8s (basado en tiempo real): la segunda desviación llega
      // milisegundos después, no debe disparar un tercer fetch.
      expect(mapService.fetchCount, 2);
    });
  });

  group('pickupProgress', () {
    setUp(setUpViewModel);

    test('avanza de 0 hacia 1 conforme el conductor se acerca al cliente', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));
      expect(vm.pickupProgress, closeTo(0.0, 0.01));

      final cercano = _offsetMeters(conductorInicial, northMeters: -200);
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: cercano));

      await _pumpUntil(() => vm.pickupProgress > 0.3);
    });
  });

  group('cancelSolicitud', () {
    setUp(setUpViewModel);

    test('delega en el servicio, limpia cache y refleja isCancelling en el ciclo', () async {
      await emitirYEsperar(_solicitud(cliente: clientePos, conductor: conductorInicial));

      final estados = <bool>[];
      vm.addListener(() => estados.add(vm.isCancelling));

      await vm.cancelSolicitud();

      expect(firebaseService.cancelCount, 1);
      expect(firebaseService.lastCancelledBy, _clienteId);
      expect(estados, contains(true));
      expect(vm.isCancelling, false);
    });
  });

  group('Restauración desde cache', () {
    test('init() puebla solicitud/ruta desde cache antes de la primera emisión del stream', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = LocalCacheService();
      final cacheada = _solicitud(cliente: clientePos, conductor: conductorInicial);
      await cache.saveSolicitud(cacheada);
      await cache.saveRoute(
        solicitudId: _solicitudId,
        points: [conductorInicial, clientePos],
        distanceMeters: 500,
        etaSeconds: 60,
      );

      solicitudController = StreamController<SolicitudModel>.broadcast();
      firebaseService = FakeTripTrackingFirebaseService(solicitudController.stream);
      mapService = FakeMapService();
      chatService = FakeChatService();

      vm = TripTrackingViewModel(
        solicitudId: _solicitudId,
        currentUserId: _clienteId,
        cancelledBy: _clienteId,
        firebaseService: firebaseService,
        mapService: mapService,
        chatService: chatService,
        localCacheService: cache,
      );
      await vm.init();

      expect(vm.solicitud?.id, _solicitudId);
      expect(vm.isLoading, false);
      expect(vm.routePointsNotifier.value.length, greaterThanOrEqualTo(2));
      // Cache restaurado, no debería haber pedido ruta nueva todavía (aún no
      // llegó ninguna emisión del stream real).
      expect(mapService.fetchCount, 0);
    });
  });
}
