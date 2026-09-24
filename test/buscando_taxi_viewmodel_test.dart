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
    required Stream<Map<String, ConductorConectado>> conectadosStream,
    super.firestore,
  }) : _conductoresStream = conductoresStream,
       _conectadosStream = conectadosStream;

  final Stream<Map<String, LatLng>> _conductoresStream;
  final Stream<Map<String, ConductorConectado>> _conectadosStream;
  int marcarCanceladaCount = 0;

  @override
  Stream<Map<String, LatLng>> streamConductoresDisponibles() =>
      _conductoresStream;

  @override
  Stream<Map<String, ConductorConectado>> streamConductoresConectados() =>
      _conectadosStream;

  @override
  Future<String?> marcarCanceladaPorInactividad() async {
    marcarCanceladaCount++;
    return null;
  }

  /// Toca `NotificacionesServicio` (no mockeado en este entorno) — se anula
  /// para poder cruzar los 300 s del primer hito sin salir a Crashlytics.
  int avisarProponerOfertaCount = 0;

  @override
  Future<void> avisarProponerOferta() async {
    avisarProponerOfertaCount++;
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
  late StreamController<Map<String, ConductorConectado>> conectadosController;
  late _FakeBuscandoTaxiViewModel vm;

  setUp(() {
    conductoresController = StreamController<Map<String, LatLng>>.broadcast();
    conectadosController =
        StreamController<Map<String, ConductorConectado>>.broadcast();
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
    // Este grupo se queda por debajo de los 300 s: los hitos que se disparan
    // al cruzarlos tienen su propio grupo más abajo.
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

  // Lo que mantiene viva la búsqueda es que el cliente CONTESTE, no el reloj:
  // cada 5 min se le propone cambiar la oferta, y si deja una propuesta sin
  // responder 5 min, la solicitud se cancela sola.
  group('hitos del contador', () {
    const proponer = BuscandoTaxiViewModel.segundosProponerOferta;
    const sinRespuesta = BuscandoTaxiViewModel.segundosSinRespuestaParaCancelar;

    test('no propone nada antes de los 5 minutos', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer - 1));

        expect(vm.eventoPendiente, isNull);
        expect(vm.avisarProponerOfertaCount, 0);
      });
    });

    test('propone cambiar la oferta a los 5 minutos', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));

        expect(vm.eventoPendiente, EventoBusqueda.proponerCambioOferta);
        // La notificación local acompaña al modal: con la app en segundo
        // plano es lo único que se ve.
        expect(vm.avisarProponerOfertaCount, 1);
      });
    });

    test('la propuesta no se vuelve a levantar tras consumirla', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));
        vm.consumirEvento();

        async.elapse(const Duration(seconds: 60));
        expect(vm.eventoPendiente, isNull);
        expect(vm.avisarProponerOfertaCount, 1);
      });
    });

    test('sin respuesta, 5 min después cancela por inactividad', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));
        vm.consumirEvento();
        vm.registrarPropuestaMostrada();

        async.elapse(Duration(seconds: sinRespuesta - 1));
        expect(vm.eventoPendiente, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(vm.eventoPendiente, EventoBusqueda.canceladaPorInactividad);
      });
    });

    // El bug que este caso fija: si el reloj de silencio arrancara al
    // LEVANTAR el evento, una vista que no puede mostrar el diálogo (hay
    // otro modal encima, se está desmontando) cancelaría la solicitud sin
    // haberle preguntado nada al cliente.
    test('si el diálogo nunca se mostró, no cancela: reagenda', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));
        expect(vm.eventoPendiente, EventoBusqueda.proponerCambioOferta);
        vm.consumirEvento(); // la vista lo descarta sin abrir nada

        // Pasa de largo el plazo de silencio y NO cancela.
        async.elapse(Duration(seconds: sinRespuesta + 60));
        expect(
          vm.eventoPendiente,
          isNot(EventoBusqueda.canceladaPorInactividad),
        );

        // Y el VM no quedó inerte: vuelve a proponer.
        expect(vm.eventoPendiente, EventoBusqueda.proponerCambioOferta);
      });
    });

    test('marcarFlujoTerminado corta los hitos en curso', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));
        vm.consumirEvento();
        vm.registrarPropuestaMostrada();

        // El cliente aceptó una oferta mientras el diálogo estaba abierto.
        // `marcarFlujoTerminado` NO cancela el search timer (eso pasa recién
        // en `finalizarTrackingConductores`, tras un await), así que sin el
        // guard el VM seguiría notificando y cancelando por detrás.
        vm.marcarFlujoTerminado();
        final avisosAntes = vm.avisarProponerOfertaCount;

        async.elapse(Duration(seconds: sinRespuesta + proponer));
        expect(vm.eventoPendiente, isNull);
        expect(vm.avisarProponerOfertaCount, avisosAntes);
      });
    });

    test('si el cliente responde, vuelve a proponer 5 min después', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));
        vm.consumirEvento();
        vm.registrarPropuestaMostrada();
        vm.registrarRespuestaOferta();

        // La cuenta de silencio quedó apagada: pasa el plazo y no cancela.
        async.elapse(Duration(seconds: proponer - 1));
        expect(vm.eventoPendiente, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(vm.eventoPendiente, EventoBusqueda.proponerCambioOferta);
        expect(vm.avisarProponerOfertaCount, 2);
      });
    });

    test('responder siempre mantiene la búsqueda viva', () {
      fakeAsync((async) {
        vm.startSearchTimer();
        for (var ronda = 0; ronda < 4; ronda++) {
          async.elapse(Duration(seconds: proponer));
          expect(vm.eventoPendiente, EventoBusqueda.proponerCambioOferta);
          vm.consumirEvento();
          vm.registrarPropuestaMostrada();
          vm.registrarRespuestaOferta();
        }
        expect(vm.eventoPendiente, isNull);
        expect(vm.searchSeconds, proponer * 4);
      });
    });

    test('notifica a los listeners en el MISMO tick que levanta el evento', () {
      fakeAsync((async) {
        // Leer el campo después del `elapse` no distingue "se levantó y se
        // notificó" de "se levantó y nadie se enteró": la vista abre el
        // modal desde el listener, así que lo que hay que fijar es qué veía
        // el listener EN el momento de la notificación. Sin esto, mover el
        // `_safeNotify()` antes de evaluar los hitos pasa desapercibido.
        // Se anota EN QUÉ SEGUNDO lo vio el listener: notificar un tick
        // tarde también sirve para que el modal salga, así que la única
        // forma de fijar el orden es exigir el segundo exacto.
        final vistos = <int>[];
        vm.addListener(() {
          if (vm.eventoPendiente == EventoBusqueda.proponerCambioOferta) {
            vistos.add(vm.searchSeconds);
          }
        });

        vm.startSearchTimer();
        async.elapse(Duration(seconds: proponer));

        expect(vistos, [proponer]);
      });
    });
  });

  // Los íconos del mapa salen de acá: solo los conductores con señal de vida
  // reciente cuentan como activos.
  group('conductoresActivos', () {
    ConductorConectado conectado({
      required Duration hace,
      bool isMoto = false,
    }) => ConductorConectado(
      ubicacion: const LatLng(8.24, -73.35),
      isMoto: isMoto,
      visto: DateTime.now().subtract(hace),
    );

    test('incluye a los vistos dentro de la ventana', () async {
      vm.subscribeConductoresConectados();
      conectadosController.add({
        'reciente': conectado(hace: const Duration(minutes: 2)),
      });
      await Future<void>.delayed(Duration.zero);

      expect(vm.conductoresActivos, hasLength(1));
    });

    test('excluye a los que pasaron la ventana', () async {
      vm.subscribeConductoresConectados();
      conectadosController.add({
        'viejo': conectado(hace: const Duration(minutes: 6)),
      });
      await Future<void>.delayed(Duration.zero);

      expect(vm.conductoresActivos, isEmpty);
      // El snapshot sigue crudo: el filtro es de lectura, no de recepción.
      expect(vm.conectados, hasLength(1));
    });

    test('conserva el tipo de vehículo de cada conductor', () async {
      vm.subscribeConductoresConectados();
      conectadosController.add({
        'moto': conectado(hace: const Duration(minutes: 1), isMoto: true),
        'carro': conectado(hace: const Duration(minutes: 1)),
      });
      await Future<void>.delayed(Duration.zero);

      final activos = vm.conductoresActivos;
      expect(activos.where((c) => c.isMoto), hasLength(1));
      expect(activos.where((c) => !c.isMoto), hasLength(1));
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

      conectadosController.add({
        'c2': ConductorConectado(
          ubicacion: const LatLng(11.0, 11.0),
          isMoto: false,
          visto: DateTime.now(),
        ),
      });
      await Future<void>.delayed(Duration.zero);
      expect(vm.conectados.keys, ['c2']);

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
        expect(
          vm.searchSeconds,
          secondsAfterStop,
          reason: 'search timer debe estar detenido',
        );

        conectadosController.add({
          'c2': ConductorConectado(
            ubicacion: const LatLng(11.0, 11.0),
            isMoto: false,
            visto: DateTime.now(),
          ),
        });
        async.flushMicrotasks();
        expect(
          vm.conectados,
          isEmpty,
          reason: 'conectadosSub debe estar cancelada',
        );

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
          StreamController<Map<String, ConductorConectado>>.broadcast();
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
    late StreamController<Map<String, ConductorConectado>> c2;

    const solicitudId = 'sol-1';

    setUp(() async {
      // `iniciarEscucha` persiste la solicitud activa vía SessionHelper; sin
      // este mock el plugin no existe y el fallo ensucia la salida del test.
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      c1 = StreamController<Map<String, LatLng>>.broadcast();
      c2 = StreamController<Map<String, ConductorConectado>>.broadcast();
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

        await firestore.collection('solicitudes').doc(solicitudId).update({
          'estado': estado,
        });
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

    test(
      'si onTerminada falla, NO se re-arma para el próximo snapshot',
      () async {
        // El `catch { _terminadaHandled = false; }` que había re-armaba el
        // one-shot: si la salida tiraba (p.ej. un `Navigator` sobre un context
        // ya desactivado), el siguiente estado terminal volvía a entrar y
        // disparaba una SEGUNDA navegación con `clearStackOnNext`. Dos de esas
        // dejaban el Navigator con una sola ruta y Flutter cerraba la app.
        var llamadas = 0;
        terminalVm.iniciarEscucha(
          solicitudId: solicitudId,
          onAsignada: (_) async {},
          onTerminada: (_) async {
            llamadas++;
            throw StateError('la salida falló');
          },
        );
        final doc = firestore.collection('solicitudes').doc(solicitudId);

        await doc.update({'estado': SolicitudEstado.cancelado});
        await pumpEventQueue();
        await doc.update({'estado': SolicitudEstado.sinRespuesta});
        await pumpEventQueue();

        expect(llamadas, 1);
      },
    );

    test(
      'asignado sigue navegando al viaje y no dispara onTerminada',
      () async {
        final asignadas = <String>[];
        final terminales = escuchar(asignadas: asignadas);

        await firestore.collection('solicitudes').doc(solicitudId).update({
          'estado': SolicitudEstado.asignado,
        });
        await pumpEventQueue();

        expect(asignadas, [solicitudId]);
        expect(terminales, isEmpty);
        expect(terminalVm.notificacionEntranteCount, 1);
      },
    );

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
