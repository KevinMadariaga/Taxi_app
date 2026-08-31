import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_info_conductor_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/participante_viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/controladores/chat_controller.dart';
import 'package:taxi_app/core/services/chat_firestore_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/conductor_perfil_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/driver_ubicacion_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/navegacion_externa_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/finalizar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/iniciar_ruta_destino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/reportar_llegada_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/viewmodels/viaje_conductor_viewmodel.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

import 'test_helpers/firebase_test_setup.dart';

/// Cobertura de los guards del viaje del conductor: el flujo "Ya llegué al
/// punto → modal de espera → PIN → en ruta → terminar". Antes no había
/// ningún test de este viewmodel.

/// Bitácora COMPARTIDA por los dos fakes. Sin esto no se puede verificar el
/// orden entre repositorios distintos: un fake solo ve sus propias escrituras.
class _Bitacora {
  final escrituras = <String>[];
}

class _FakeViajeRepository implements ViajeRepository {
  _FakeViajeRepository(this._bitacora);

  final _Bitacora _bitacora;
  final estados = <String>[];
  Object? errorAlActualizar;
  int llamadasActualizar = 0;

  final _viajes = StreamController<ViajeEntity>.broadcast();

  /// Empuja un snapshot como lo haría Firestore — necesario para ejercitar
  /// `_handleEstadoTransition`, que es donde vive el guard de la modal.
  void emitir(ViajeEntity viaje) => _viajes.add(viaje);

  @override
  Stream<ViajeEntity> watchViaje(String viajeId) => _viajes.stream;

  @override
  Future<void> actualizarEstado({
    required String viajeId,
    required String estado,
    Map<String, dynamic>? extra,
  }) async {
    llamadasActualizar++;
    if (errorAlActualizar != null) throw errorAlActualizar!;
    estados.add(estado);
    _bitacora.escrituras.add('estado:$estado');
  }

  @override
  Future<void> cancelar({
    required String viajeId,
    required String canceladoPor,
  }) async {}

  final infoConductorActualizada = <Map<String, dynamic>>[];

  @override
  Future<void> actualizarInfoConductor({
    required String viajeId,
    required Map<String, dynamic> datosConductor,
  }) async {
    infoConductorActualizada.add(datosConductor);
    _bitacora.escrituras.add('infoConductor:${datosConductor.keys.join(",")}');
  }
}

class _FakeCodigoRepository implements CodigoVerificacionRepository {
  _FakeCodigoRepository(this._bitacora);

  final _Bitacora _bitacora;
  CodigoVerificacionEntity? almacenado;
  Object? errorAlGuardar;
  int guardados = 0;
  int validaciones = 0;

  @override
  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId) async =>
      almacenado;

  @override
  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId) =>
      const Stream.empty();

  @override
  Future<void> guardarCodigo(
    String viajeId,
    CodigoVerificacionEntity codigo,
  ) async {
    guardados++;
    if (errorAlGuardar != null) throw errorAlGuardar!;
    almacenado = codigo;
    _bitacora.escrituras.add('codigo');
  }

  @override
  Future<void> marcarValidado(String viajeId) async {
    validaciones++;
    almacenado = almacenado?.copyWith(validadoEn: DateTime(2026, 1, 1));
  }

  @override
  Future<void> incrementarIntentoFallido(String viajeId) async {}
}

/// Chat que nunca emite — el flujo bajo prueba no lo usa, pero `init()` lo
/// enlaza y sin fake pega contra el canal real de Firestore.
class _FakeChatDatasource extends ChatFirestoreDatasource {
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrderedMessages(
    String solicitudId,
  ) => const Stream.empty();
}

const _participante = ParticipanteViajeEntity(
  id: 'x',
  nombre: 'Ana',
  fotoUrl: '',
  fotoVehiculoUrl: '',
  placaVehiculo: '',
  calificacion: 5,
  totalCalificaciones: 1,
  direccion: 'Calle 1',
  ubicacion: LatLng(4.60, -74.08),
);

ViajeEntity _viaje(
  String estado, {
  DateTime? esperaIniciadaEn,
  String metodoPago = '',
}) => ViajeEntity(
  id: 'v1',
  estado: estado,
  cliente: _participante,
  conductor: _participante,
  destino: const DestinoViajeEntity(
    direccion: 'Destino',
    ubicacion: LatLng(4.65, -74.05),
  ),
  updatedAt: DateTime(2026, 1, 1),
  esperaIniciadaEn: esperaIniciadaEn,
  metodoPago: metodoPago,
);

class _Fixture {
  factory _Fixture({DateTime Function()? now}) {
    final bitacora = _Bitacora();
    return _Fixture._(
      bitacora,
      _FakeViajeRepository(bitacora),
      _FakeCodigoRepository(bitacora),
      now,
    );
  }

  _Fixture._(this.bitacora, this.viajeRepo, this.codigoRepo, DateTime Function()? now) {
    final actualizar = ActualizarEstadoViajeUseCase(viajeRepo);
    vm = ViajeConductorViewModel(
      viajeId: 'v1',
      conductorId: 'c1',
      watchViaje: WatchViajeUseCase(viajeRepo),
      actualizarEstado: actualizar,
      now: now,
      reportarLlegada: ReportarLlegadaUseCase(
        actualizarEstado: actualizar,
        generarCodigo: GenerarCodigoVerificacionUseCase(codigoRepo),
      ),
      iniciarRutaDestino: IniciarRutaDestinoUseCase(
        actualizarEstado: actualizar,
        validarCodigo: ValidarCodigoVerificacionUseCase(codigoRepo),
      ),
      finalizarViaje: FinalizarViajeUseCase(actualizar),
      actualizarInfoConductor: ActualizarInfoConductorEnViajeUseCase(viajeRepo),
      // Firestore fake: sin esto, `_bindPerfilConductor` (que sí se activa
      // porque `actualizarInfoConductor` está seteado arriba) pegaría contra
      // el plugin real de `cloud_firestore`, no mockeado en este test.
      perfilDatasource: ConductorPerfilDatasource(
        firestore: FakeFirebaseFirestore(),
      ),
      ubicacionDatasource: DriverUbicacionDatasource(),
      rutaDatasource: RutaDatasource(),
      navegacionDatasource: NavegacionExternaDatasource(),
      chatController: ChatController(
        viajeId: 'v1',
        currentUserId: 'c1',
        otherPartyLabel: 'cliente',
        // Sin esto, `init()` llama `chat.bind()` y pega contra el canal real
        // de Firestore (`channel-error`), que en test no existe.
        datasource: _FakeChatDatasource(),
      ),
    );
  }

  final _Bitacora bitacora;
  final _FakeViajeRepository viajeRepo;
  final _FakeCodigoRepository codigoRepo;
  late final ViajeConductorViewModel vm;
}

void main() {
  // Los tests no llaman `vm.dispose()`: ese `dispose` invoca
  // `NotificacionesServicio.cancelAll`, que sin el plugin nativo lanza
  // `LateInitializationError` (es un `late static` del platform interface, no
  // un MethodChannel mockeable). Acá el VM nunca abre stream ni tracking.
  setUpAll(setupFirebaseForTests);

  group('reportarLlegada', () {
    test('genera el código ANTES de mover el estado', () async {
      final f = _Fixture();

      await f.vm.reportarLlegada();

      // Bitácora compartida por los dos repos: es la única forma de ver el
      // entrelazado real entre la escritura del código y la del estado.
      expect(f.bitacora.escrituras, [
        'codigo',
        'estado:${SolicitudEstado.enEspera}',
      ]);
      expect(f.vm.hasReportedArrival, isTrue);
    });

    test(
      'si falla generar el código, el estado NO se mueve y se puede reintentar',
      () async {
        final f = _Fixture();
        f.codigoRepo.errorAlGuardar = StateError('sin red');

        await f.vm.reportarLlegada();

        // El viaje sigue en `asignado`: el botón "Ya llegué al punto" queda
        // activo en vez de dejarlo varado en `en espera` sin código.
        expect(f.viajeRepo.estados, isEmpty);
        expect(f.vm.hasReportedArrival, isFalse);
        expect(f.vm.errorText, contains('No se pudo reportar la llegada'));

        // Y el reintento funciona.
        f.codigoRepo.errorAlGuardar = null;
        await f.vm.reportarLlegada();
        expect(f.viajeRepo.estados, [SolicitudEstado.enEspera]);
      },
    );

    test('no se dispara dos veces con doble tap', () async {
      final f = _Fixture();

      await Future.wait([f.vm.reportarLlegada(), f.vm.reportarLlegada()]);

      expect(f.codigoRepo.guardados, 1);
      expect(f.viajeRepo.estados, [SolicitudEstado.enEspera]);
    });
  });

  group('modal de espera vs. sheet del PIN', () {
    test('mientras el PIN está abierto la modal de espera no vuelve', () async {
      final f = _Fixture();
      // El viaje arranca en `asignado` para que la transición a `en espera`
      // sea real: un `notifyListeners()` pelado NO alcanza — el que reabría
      // la modal era `_handleEstadoTransition`, y sin cambio de estado ese
      // camino ni se ejecuta (el test anterior pasaba con y sin el fix).
      f.viajeRepo.emitir(_viaje(SolicitudEstado.asignado));
      await f.vm.init();
      await pumpEventQueue();

      f.vm.abrirIngresoCodigo();
      expect(f.vm.codigoSheetVisible, isTrue);
      expect(f.vm.waitingModalVisible, isFalse);

      // Llega el snapshot con el estado que dispara la modal de espera,
      // justo con el sheet del PIN abierto.
      f.viajeRepo.emitir(_viaje(SolicitudEstado.enEspera));
      await pumpEventQueue();

      expect(
        f.vm.waitingModalVisible,
        isFalse,
        reason: 'la modal se reabrió encima del sheet del PIN',
      );
    });

    test('al descartar el PIN sin validar, la modal de espera vuelve', () {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.enCamino);

      f.vm.abrirIngresoCodigo();
      f.vm.cerrarIngresoCodigo();

      expect(f.vm.codigoSheetVisible, isFalse);
      expect(f.vm.waitingModalVisible, isTrue);
      // `en camino` = el cliente ya confirmó: se puede arrancar de inmediato.
      expect(f.vm.waitingCanStartTrip, isTrue);
    });

    test('volver del PIN no reinicia el plazo de 180 s', () {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.enEspera);
      f.vm.waitingRemainingSeconds = 42;

      f.vm.abrirIngresoCodigo();
      f.vm.cerrarIngresoCodigo();

      expect(f.vm.waitingRemainingSeconds, 42);
    });

    test('en estado terminal el PIN no revive la modal', () {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.cancelado);

      f.vm.abrirIngresoCodigo();
      f.vm.cerrarIngresoCodigo();

      expect(f.vm.waitingModalVisible, isFalse);
    });
  });

  group('temporizador de espera: ancla de servidor', () {
    test(
      'con esperaIniciadaEn ya escrito en el pasado, arranca en el '
      'remanente real y no en 180',
      () async {
        final ahora = DateTime(2026, 1, 1, 12, 0, 30);
        final f = _Fixture(now: () => ahora);
        // `init()` PRIMERO: el fake usa un `StreamController.broadcast`, así
        // que un `emitir()` antes de suscribirse (antes de `init()`) se
        // pierde sin avisar — el listener todavía no existe.
        await f.vm.init();
        // Snapshot en `asignado` para que la transición a `en espera` sea
        // real — mismo motivo que el primer test del grupo anterior.
        f.viajeRepo.emitir(_viaje(SolicitudEstado.asignado));
        await pumpEventQueue();

        f.viajeRepo.emitir(
          _viaje(
            SolicitudEstado.enEspera,
            esperaIniciadaEn: DateTime(2026, 1, 1, 12, 0, 0),
          ),
        );
        await pumpEventQueue();

        // 30s ya transcurridos según el ancla -> quedan 150, no 180.
        expect(f.vm.waitingRemainingSeconds, 150);
      },
    );

    test(
      'la deriva del timer local de 1s se corrige en cada snapshot '
      'mientras la modal sigue contando',
      () async {
        var ahora = DateTime(2026, 1, 1, 12, 0, 30);
        final f = _Fixture(now: () => ahora);
        await f.vm.init();
        f.viajeRepo.emitir(_viaje(SolicitudEstado.asignado));
        await pumpEventQueue();

        final inicio = DateTime(2026, 1, 1, 12, 0, 0);
        f.viajeRepo.emitir(
          _viaje(SolicitudEstado.enEspera, esperaIniciadaEn: inicio),
        );
        await pumpEventQueue();
        expect(f.vm.waitingRemainingSeconds, 150);

        // Otro snapshot llega más tarde sin que el ESTADO cambie (p. ej. un
        // ping GPS del propio conductor, que escribe en la misma
        // solicitud) — el remanente se resincroniza contra el ancla real
        // en vez de seguir solo el conteo local.
        ahora = DateTime(2026, 1, 1, 12, 1, 0);
        f.viajeRepo.emitir(
          _viaje(SolicitudEstado.enEspera, esperaIniciadaEn: inicio),
        );
        await pumpEventQueue();
        expect(f.vm.waitingRemainingSeconds, 120);
      },
    );
  });

  group('cambio de método de pago avisa al conductor', () {
    test(
      'un segundo snapshot con otro método levanta el aviso pendiente',
      () async {
        final f = _Fixture();
        await f.vm.init();
        f.viajeRepo.emitir(
          _viaje(SolicitudEstado.asignado, metodoPago: 'Efectivo'),
        );
        await pumpEventQueue();
        expect(f.vm.cambioMetodoPagoPendiente, isFalse);

        f.viajeRepo.emitir(
          _viaje(SolicitudEstado.asignado, metodoPago: 'Nequi'),
        );
        await pumpEventQueue();

        expect(f.vm.cambioMetodoPagoPendiente, isTrue);
        expect(f.vm.metodoPagoAvisado, 'Nequi');

        f.vm.consumirAvisoCambioMetodoPago();
        expect(f.vm.cambioMetodoPagoPendiente, isFalse);
      },
    );

    test('mismo valor con distinta capitalización no cuenta como cambio', () async {
      final f = _Fixture();
      await f.vm.init();
      f.viajeRepo.emitir(
        _viaje(SolicitudEstado.asignado, metodoPago: 'Efectivo'),
      );
      await pumpEventQueue();

      f.viajeRepo.emitir(
        _viaje(SolicitudEstado.asignado, metodoPago: 'EFECTIVO'),
      );
      await pumpEventQueue();

      expect(f.vm.cambioMetodoPagoPendiente, isFalse);
    });

    test('el primer snapshot (línea base) nunca cuenta como cambio', () async {
      final f = _Fixture();
      await f.vm.init();
      f.viajeRepo.emitir(
        _viaje(SolicitudEstado.asignado, metodoPago: 'Nequi'),
      );
      await pumpEventQueue();

      expect(f.vm.cambioMetodoPagoPendiente, isFalse);
    });
  });

  group('validarCodigoRecogida', () {
    test('un segundo intento concurrente devuelve enProceso y no escribe dos '
        'veces', () async {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.enCamino);
      f.codigoRepo.almacenado = CodigoVerificacionEntity(
        codigo: '1234',
        generadoEn: DateTime(2026, 1, 1),
        validadoEn: null,
      );

      final primero = f.vm.validarCodigoRecogida('1234');
      final segundo = f.vm.validarCodigoRecogida('1234');

      expect(await segundo, ResultadoValidacionCodigo.enProceso);
      expect(await primero, ResultadoValidacionCodigo.correcto);
      expect(f.codigoRepo.validaciones, 1);
      expect(f.viajeRepo.estados, [SolicitudEstado.enRuta]);
    });
  });

  group('finalizarViaje', () {
    test('el doble tap escribe una sola vez', () async {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.enRuta);

      await Future.wait([f.vm.finalizarViaje(), f.vm.finalizarViaje()]);

      expect(f.viajeRepo.estados, [SolicitudEstado.completado]);
      expect(f.vm.isFinalizandoViaje, isFalse);
    });

    test(
      'un fallo deja mensaje de error en vez de perderse en silencio',
      () async {
        final f = _Fixture();
        f.vm.viaje = _viaje(SolicitudEstado.enRuta);
        f.viajeRepo.errorAlActualizar = StateError('permiso denegado');

        await f.vm.finalizarViaje();

        expect(f.vm.errorText, contains('No se pudo terminar el viaje'));
        expect(f.vm.isFinalizandoViaje, isFalse);
      },
    );

    test('limpiarError borra el mensaje una vez mostrado', () async {
      final f = _Fixture();
      f.vm.viaje = _viaje(SolicitudEstado.enRuta);
      f.viajeRepo.errorAlActualizar = StateError('x');

      await f.vm.finalizarViaje();
      expect(f.vm.errorText, isNotNull);

      f.vm.limpiarError();
      expect(f.vm.errorText, isNull);
    });
  });
}
