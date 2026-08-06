// Tests de caracterización de BuscandoTaxiViewModel — paso 3 del refactor de
// buscando_taxi_view.dart (ver graphify-out — comunidad "Usuario Cliente
// Presentacion View — Buscando Taxi View" quedó como la de cohesión más baja
// del repo tras el refactor de trip_tracking_viewmodel).
//
// Cubre específicamente lo que se movió DESDE la View hacia el vm en este
// paso: streams de posiciones de conductores + los 3 timers de ciclo de vida
// (aviso a los 5min, cancelar tras 6min en background, cancelar 2s tras
// detached) — antes vivían en el State del widget (riesgo #2 de CLAUDE.md:
// listener de Firestore en la View, no en el ViewModel).
//
// A diferencia de trip_tracking_viewmodel_test.dart, acá SÍ usamos
// `fake_async`: ninguno de los timers movidos lee `DateTime.now()`
// internamente (solo cuentan ticks / duración fija de un Timer), así que
// fake_async controla el tiempo de punta a punta sin el problema de
// DateTime.now() no interceptado que sí aplicaba al motor de movimiento.
//
// Fuera de alcance: el resto del vm (binding a la solicitud, aceptar/rechazar
// contraoferta, actualizar valor) ya existía antes de este refactor y no se
// tocó — no se caracteriza acá.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';

import 'test_helpers/firebase_test_setup.dart';

/// Sustituye los streams de Firestore (única I/O externa de los métodos que
/// se caracterizan acá) y `marcarCanceladaPorInactividad` (para no requerir
/// un documento real) por subclassing — mismo patrón que las fakes de
/// trip_tracking.
class _FakeBuscandoTaxiViewModel extends BuscandoTaxiViewModel {
  _FakeBuscandoTaxiViewModel({
    required Stream<Map<String, LatLng>> conductoresStream,
    required Stream<Map<String, LatLng>> conectadosStream,
    super.firestore,
  }) : _conductoresStream = conductoresStream,
       _conectadosStream = conectadosStream;

  final Stream<Map<String, LatLng>> _conductoresStream;
  final Stream<Map<String, LatLng>> _conectadosStream;
  int marcarCanceladaCount = 0;

  @override
  Stream<Map<String, LatLng>> streamConductoresDisponibles() =>
      _conductoresStream;

  @override
  Stream<Map<String, LatLng>> streamConductoresConectados() =>
      _conectadosStream;

  @override
  Future<void> marcarCanceladaPorInactividad() async {
    marcarCanceladaCount++;
  }

  /// Toca `NotificacionesServicio` (no mockeado en este entorno) — se anula
  /// para poder ejercitar la rama `asignado` de `iniciarEscucha`.
  int notificacionEntranteCount = 0;

  @override
  Future<void> mostrarNotificacionSolicitudEntrante() async {
    notificacionEntranteCount++;
  }
}

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });

  late StreamController<Map<String, LatLng>> conductoresController;
  late StreamController<Map<String, LatLng>> conectadosController;
  late _FakeBuscandoTaxiViewModel vm;

  setUp(() {
    conductoresController = StreamController<Map<String, LatLng>>.broadcast();
    conectadosController = StreamController<Map<String, LatLng>>.broadcast();
    vm = _FakeBuscandoTaxiViewModel(
      conductoresStream: conductoresController.stream,
      conectadosStream: conectadosController.stream,
    );
  });

  tearDown(() async {
    vm.dispose();
    await conductoresController.close();
    await conectadosController.close();
  });

  group('startSearchTimer', () {
    // No se llega a `segundosAviso5min` (300s) a propósito: cruzarlo dispara
    // `_avisar5Minutos()` -> `NotificacionesServicio` -> `ErrorReporter` ->
    // Crashlytics, ninguno mockeado en este entorno (mismo gap preexistente
    // en todo el repo: ErrorReporter.report no tiene try/catch propio). No es
    // parte de lo que se caracteriza acá (el conteo de segundos en sí).
    test('cuenta segundos cada tick', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        expect(vm.searchSeconds, 0);

        async.elapse(const Duration(seconds: 30));
        expect(vm.searchSeconds, 30);

        async.elapse(const Duration(seconds: 220));
        expect(vm.searchSeconds, 250);
      });
    });

    test('reinicia el contador si se llama de nuevo', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(const Duration(seconds: 10));
        expect(vm.searchSeconds, 10);

        vm.startSearchTimer();
        expect(vm.searchSeconds, 0);
        async.elapse(const Duration(seconds: 5));
        expect(vm.searchSeconds, 5);
      });
    });
  });

  group('handleAppLifecycleState — background (6 min)', () {
    test('cancela por inactividad tras 6 min en paused', () {
      fakeAsync((async) {
        vm.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 6));
        expect(vm.marcarCanceladaCount, 1);
      });
    });

    test('no cancela antes de los 6 min', () {
      fakeAsync((async) {
        vm.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5, seconds: 59));
        expect(vm.marcarCanceladaCount, 0);
      });
    });

    test('resumed antes de los 6 min cancela el timer pendiente', () {
      fakeAsync((async) {
        vm.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 3));
        vm.handleAppLifecycleState(AppLifecycleState.resumed);
        // Si el timer no se hubiera cancelado, a los 6 min totales dispararía.
        async.elapse(const Duration(minutes: 4));
        expect(vm.marcarCanceladaCount, 0);
      });
    });
  });

  group('handleAppLifecycleState — detached (2 s)', () {
    test('cancela por inactividad 2 s tras detached', () {
      fakeAsync((async) {
        vm.handleAppLifecycleState(AppLifecycleState.detached);
        async.elapse(const Duration(seconds: 2));
        expect(vm.marcarCanceladaCount, 1);
      });
    });
  });

  group('marcarFlujoTerminado', () {
    test('impide que timers de ciclo de vida futuros disparen cancelación', () {
      fakeAsync((async) {
        vm.marcarFlujoTerminado();
        vm.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 6));
        expect(vm.marcarCanceladaCount, 0);
      });
    });

    test('cancela un timer de background ya en curso', () {
      fakeAsync((async) {
        vm.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 1));
        vm.marcarFlujoTerminado();
        async.elapse(const Duration(minutes: 5));
        expect(vm.marcarCanceladaCount, 0);
      });
    });
  });

  group('subscribeConductores / subscribeConductoresConectados', () {
    test('actualizan las posiciones y notifican listeners', () async {
      var notifyCount = 0;
      vm.addListener(() => notifyCount++);

      vm.subscribeConductores();
      vm.subscribeConductoresConectados();

      conductoresController.add({'c1': const LatLng(10.0, 10.0)});
      await Future<void>.delayed(Duration.zero);
      expect(vm.conductoresPositions, {'c1': const LatLng(10.0, 10.0)});

      conectadosController.add({'c2': const LatLng(11.0, 11.0)});
      await Future<void>.delayed(Duration.zero);
      expect(vm.conectadosPositions, {'c2': const LatLng(11.0, 11.0)});

      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });

  group('finalizarTrackingConductores', () {
    // Antes este test fijaba la asimetría original: `_conductoresSub` NO se
    // cancelaba acá, solo en `dispose()`. Como la navegación al viaje se hace
    // con `push`, la vista seguía montada y esa suscripción —una query sin
    // cota sobre `usuarios`— quedaba corriendo durante todo el viaje.
    test('detiene el search timer y AMBAS suscripciones', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        vm.subscribeConductores();
        vm.subscribeConductoresConectados();

        vm.finalizarTrackingConductores();

        final secondsAfterStop = vm.searchSeconds;
        async.elapse(const Duration(seconds: 5));
        expect(vm.searchSeconds, secondsAfterStop, reason: 'search timer debe estar detenido');

        conectadosController.add({'c2': const LatLng(11.0, 11.0)});
        async.flushMicrotasks();
        expect(vm.conectadosPositions, isEmpty, reason: 'conectadosSub debe estar cancelada');

        conductoresController.add({'c1': const LatLng(10.0, 10.0)});
        async.flushMicrotasks();
        expect(
          vm.conductoresPositions,
          isEmpty,
          reason: 'conductoresSub también debe cancelarse al terminar el flujo',
        );
      });
    });
  });

  group('dispose', () {
    test('cancela timers y ambas suscripciones', () {
      // vm/controllers propios (no los del `setUp` compartido): este test
      // dispara dispose() explícitamente para observar su efecto, y el
      // `tearDown` global de todas formas hace `vm.dispose()` sobre la
      // variable compartida — usar una instancia separada evita un doble
      // dispose (ChangeNotifier lanza si se dispose() dos veces).
      final ownConductoresController =
          StreamController<Map<String, LatLng>>.broadcast();
      final ownConectadosController =
          StreamController<Map<String, LatLng>>.broadcast();
      final ownVm = _FakeBuscandoTaxiViewModel(
        conductoresStream: ownConductoresController.stream,
        conectadosStream: ownConectadosController.stream,
      );

      fakeAsync((async) {
        ownVm.startSearchTimer();
        ownVm.subscribeConductores();
        ownVm.subscribeConductoresConectados();
        ownVm.handleAppLifecycleState(AppLifecycleState.paused);

        ownVm.dispose();

        final secondsAtDispose = ownVm.searchSeconds;
        async.elapse(const Duration(minutes: 6));
        expect(ownVm.searchSeconds, secondsAtDispose);
        expect(ownVm.marcarCanceladaCount, 0);
      });

      ownConductoresController.close();
      ownConectadosController.close();
    });
  });

  // Regresión: antes `iniciarEscucha` solo manejaba `asignado`, así que una
  // solicitud cancelada por un admin / barrida por el job server-side de
  // inactivas / expirada a 'sin respuesta' / con el documento borrado dejaba
  // al cliente girando en "Buscando conductor" para siempre.
  group('iniciarEscucha — salida en estado terminal', () {
    late FakeFirebaseFirestore firestore;
    late _FakeBuscandoTaxiViewModel terminalVm;
    late StreamController<Map<String, LatLng>> c1;
    late StreamController<Map<String, LatLng>> c2;

    const solicitudId = 'sol-1';

    setUp(() async {
      // `iniciarEscucha` persiste la solicitud activa vía SessionHelper; sin
      // este mock el plugin no existe y el fallo ensucia la salida del test.
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      c1 = StreamController<Map<String, LatLng>>.broadcast();
      c2 = StreamController<Map<String, LatLng>>.broadcast();
      terminalVm = _FakeBuscandoTaxiViewModel(
        conductoresStream: c1.stream,
        conectadosStream: c2.stream,
        firestore: firestore,
      );
      await firestore.collection('solicitudes').doc(solicitudId).set({
        'estado': SolicitudEstado.buscando,
        'cliente': {'id': 'cli-1'},
      });
    });

    tearDown(() async {
      terminalVm.dispose();
      await c1.close();
      await c2.close();
    });

    /// Engancha el listener y devuelve los estados terminales notificados.
    List<String> escuchar({List<String>? asignadas}) {
      final terminales = <String>[];
      terminalVm.iniciarEscucha(
        solicitudId: solicitudId,
        onAsignada: (id) async => asignadas?.add(id),
        onTerminada: (estado) async => terminales.add(estado),
      );
      return terminales;
    }

    for (final estado in [
      SolicitudEstado.cancelado,
      SolicitudEstado.sinRespuesta,
      SolicitudEstado.completado,
    ]) {
      test('estado "$estado" notifica onTerminada y no onAsignada', () async {
        final asignadas = <String>[];
        final terminales = escuchar(asignadas: asignadas);

        await firestore
            .collection('solicitudes')
            .doc(solicitudId)
            .update({'estado': estado});
        await pumpEventQueue();

        expect(terminales, [estado]);
        expect(asignadas, isEmpty);
      });
    }

    test('documento borrado se reporta como cancelado', () async {
      final terminales = escuchar();

      await firestore.collection('solicitudes').doc(solicitudId).delete();
      await pumpEventQueue();

      expect(terminales, [SolicitudEstado.cancelado]);
    });

    test('onTerminada se dispara una sola vez', () async {
      final terminales = escuchar();
      final doc = firestore.collection('solicitudes').doc(solicitudId);

      await doc.update({'estado': SolicitudEstado.cancelado});
      await pumpEventQueue();
      await doc.update({'estado': SolicitudEstado.sinRespuesta});
      await pumpEventQueue();

      expect(terminales, [SolicitudEstado.cancelado]);
    });

    test('asignado sigue navegando al viaje y no dispara onTerminada', () async {
      final asignadas = <String>[];
      final terminales = escuchar(asignadas: asignadas);

      await firestore
          .collection('solicitudes')
          .doc(solicitudId)
          .update({'estado': SolicitudEstado.asignado});
      await pumpEventQueue();

      expect(asignadas, [solicitudId]);
      expect(terminales, isEmpty);
      expect(terminalVm.notificacionEntranteCount, 1);
    });

    // Un viaje ya asignado que luego se completa NO debe sacar al cliente de
    // acá con un mensaje de "búsqueda finalizada": de esa transición se
    // encarga la pantalla de viaje.
    test('completado tras asignado no dispara onTerminada', () async {
      final asignadas = <String>[];
      final terminales = escuchar(asignadas: asignadas);
      final doc = firestore.collection('solicitudes').doc(solicitudId);

      await doc.update({'estado': SolicitudEstado.asignado});
      await pumpEventQueue();
      await doc.update({'estado': SolicitudEstado.completado});
      await pumpEventQueue();

      expect(asignadas, [solicitudId]);
      expect(terminales, isEmpty);
    });
  });
}
