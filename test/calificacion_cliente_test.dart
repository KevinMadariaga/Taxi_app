import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/calificacion_cliente/dominio/entidades/calificacion_cliente.dart';
import 'package:taxi_app/caracteristicas/calificacion_cliente/dominio/repositorios/calificacion_cliente_repository.dart';
import 'package:taxi_app/caracteristicas/calificacion_cliente/presentacion/viewmodels/calificaciones_clientes_viewmodel.dart';
import 'package:taxi_app/caracteristicas/calificacion_cliente/presentacion/widgets/calificacion_cliente_badge.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/features/resumen_viaje/controllers/resumen_viaje_controller.dart';
import 'package:taxi_app/features/resumen_viaje/models/resumen_viaje_model.dart';
import 'package:taxi_app/features/resumen_viaje/services/resumen_viaje_firestore_service.dart';

import 'test_helpers/firebase_test_setup.dart';

class _FakeRepo implements CalificacionClienteRepository {
  _FakeRepo(this.datos, {this.falla = false});

  final Map<String, CalificacionCliente> datos;
  final bool falla;
  final List<String> pedidos = [];

  @override
  Future<CalificacionCliente?> obtener(String clienteId) async {
    pedidos.add(clienteId);
    if (falla) throw Exception('sin red');
    return datos[clienteId];
  }
}

class _FakeResumenService extends ResumenViajeFirebaseService {
  _FakeResumenService({this.falla = false});

  final bool falla;
  final List<({double calificacion, String comentario})> alCliente = [];

  @override
  Future<void> guardarCalificacionAlCliente({
    required String solicitudId,
    required double calificacion,
    required String comentario,
  }) async {
    if (falla) throw Exception('permission-denied');
    alCliente.add((calificacion: calificacion, comentario: comentario));
  }
}

ResumenViajeModel _resumen({double? calificacionCliente}) =>
    ResumenViajeModel.fromFirestore(
      solicitudId: 's1',
      data: {
        'cliente': {'id': 'c1', 'nombre': 'Ana'},
        'conductor': {'id': 'd1', 'nombre': 'Juan'},
        'estado': 'completado',
        'calificacion': 5,
        'calificacionCliente': ?calificacionCliente,
      },
    );

void main() {
  // ErrorReporter -> Crashlytics necesita Firebase inicializado.
  setUpAll(setupFirebaseForTests);

  group('ResumenViajeModel', () {
    test('lee el id del cliente y la calificación que le dio el conductor', () {
      final r = _resumen(calificacionCliente: 4);
      expect(r.clienteId, 'c1');
      expect(r.calificacionCliente, 4);
      // La del cliente al conductor sigue en su campo.
      expect(r.calificacion, 5);
    });
  });

  group('ResumenViajeController (conductor califica al pasajero)', () {
    late _FakeResumenService servicio;
    late ResumenViajeController vm;

    setUp(() {
      servicio = _FakeResumenService();
      vm = ResumenViajeController(
        tipoUsuario: TipoUsuarioResumen.conductor,
        solicitudId: 's1',
        firebaseService: servicio,
      );
    });

    test('es opcional: sin estrellas no escribe nada', () async {
      vm.sincronizarFormulario(_resumen());
      expect(await vm.guardarCalificacionConductor(), isNull);
      expect(servicio.alCliente, isEmpty);
    });

    test('no toma la calificación del cliente al conductor como propia', () {
      vm.sincronizarFormulario(_resumen());
      expect(vm.calificacionSeleccionada, 0);
      expect(vm.clienteYaCalificado, isFalse);
    });

    test('con menos de 3 estrellas exige comentario', () async {
      vm.sincronizarFormulario(_resumen());
      vm.setCalificacion(2);
      expect(await vm.guardarCalificacionConductor(), isNotNull);
      expect(servicio.alCliente, isEmpty);

      vm.setComentario('Llegó tarde y no avisó');
      expect(await vm.guardarCalificacionConductor(), isNull);
      expect(servicio.alCliente.single.calificacion, 2);
    });

    test('guarda una sola vez aunque se pulse de nuevo', () async {
      vm.sincronizarFormulario(_resumen());
      vm.setCalificacion(5);
      await vm.guardarCalificacionConductor();
      await vm.guardarCalificacionConductor();
      expect(servicio.alCliente, hasLength(1));
    });

    test('un fallo al guardar no deja al conductor atrapado', () async {
      final vmFalla = ResumenViajeController(
        tipoUsuario: TipoUsuarioResumen.conductor,
        solicitudId: 's1',
        firebaseService: _FakeResumenService(falla: true),
      )..sincronizarFormulario(_resumen());
      vmFalla.setCalificacion(5);
      expect(await vmFalla.guardarCalificacionConductor(), isNull);
      expect(vmFalla.guardando, isFalse);
    });

    test('si ya lo había calificado no reescribe', () async {
      vm.sincronizarFormulario(_resumen(calificacionCliente: 4));
      expect(vm.clienteYaCalificado, isTrue);
      vm.setCalificacion(1);
      expect(await vm.guardarCalificacionConductor(), isNull);
      expect(servicio.alCliente, isEmpty);
    });
  });

  group('CalificacionesClientesViewModel', () {
    test('lee cada cliente una sola vez y notifica al cargar', () async {
      final repo = _FakeRepo({
        'c1': const CalificacionCliente(promedio: 4.8, total: 12),
      });
      final vm = CalificacionesClientesViewModel(repo);
      var avisos = 0;
      vm.addListener(() => avisos++);

      expect(vm.de('c1'), isNull);
      vm.de('c1');
      await pumpEventQueue();

      expect(vm.de('c1')!.promedio, 4.8);
      expect(repo.pedidos, ['c1']);
      expect(avisos, 1);
    });

    test('un error no se reintenta en cada build', () async {
      final repo = _FakeRepo({}, falla: true);
      final vm = CalificacionesClientesViewModel(repo);
      vm.de('c1');
      await pumpEventQueue();
      vm.de('c1');
      await pumpEventQueue();
      expect(vm.cargado('c1'), isTrue);
      expect(repo.pedidos, hasLength(1));
    });
  });

  group('CalificacionClienteBadge', () {
    Future<void> montar(WidgetTester tester, _FakeRepo repo) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => CalificacionesClientesViewModel(repo),
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppPalette.light]),
            home: const Scaffold(
              body: Column(
                children: [
                  CalificacionClienteBadge(clienteId: 'c1'),
                  CalificacionClienteBadge(clienteId: 'c2'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('muestra promedio y total, o "Nuevo" sin calificaciones', (
      tester,
    ) async {
      await montar(
        tester,
        _FakeRepo({'c1': const CalificacionCliente(promedio: 4.83, total: 12)}),
      );
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);
    });

    testWidgets('sin el provider global no rompe la pantalla', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CalificacionClienteBadge(clienteId: 'c1')),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
