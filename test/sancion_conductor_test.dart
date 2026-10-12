import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taxi_app/caracteristicas/sancion_conductor/datos/repositorios/sancion_conductor_repository_impl.dart';
import 'package:taxi_app/caracteristicas/sancion_conductor/dominio/entidades/sancion_conductor.dart';
import 'package:taxi_app/caracteristicas/sancion_conductor/dominio/repositorios/sancion_conductor_repository.dart';
import 'package:taxi_app/caracteristicas/sancion_conductor/presentacion/viewmodels/pausa_cancelaciones_viewmodel.dart';
import 'package:taxi_app/caracteristicas/sancion_conductor/presentacion/widgets/pausa_cancelaciones_overlay.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/widgets/motivo_cancelacion_sheet.dart';

class _FakeRepo implements SancionConductorRepository {
  final ctrl = StreamController<SancionConductor>.broadcast();

  @override
  Stream<SancionConductor> watch(String conductorId) => ctrl.stream;

  @override
  Future<SancionConductor> obtener(String conductorId) async =>
      SancionConductor.ninguna;
}

void main() {
  final t0 = DateTime(2026, 10, 11, 12);

  group('SancionConductor', () {
    test('restante desde bloqueadoHasta; cero si venció o no hay', () {
      final s = SancionConductor(
        bloqueadoHasta: t0.add(const Duration(minutes: 15)),
      );
      expect(s.restante(t0), const Duration(minutes: 15));
      expect(s.restante(t0.add(const Duration(minutes: 16))), Duration.zero);
      expect(SancionConductor.ninguna.restante(t0), Duration.zero);
    });

    test('aviso solo cerca del límite, contando la ventana de 24 h', () {
      List<DateTime> hace(int n, Duration d) => List.filled(n, t0.subtract(d));
      SancionConductor con(List<DateTime> c) =>
          SancionConductor(cancelaciones: c);

      expect(
        con(hace(3, const Duration(hours: 1))).avisoAntesDeCancelar(t0),
        isNull,
      );
      expect(
        con(hace(4, const Duration(hours: 1))).avisoAntesDeCancelar(t0),
        contains('Llevas 4'),
      );
      expect(
        con(hace(5, const Duration(hours: 1))).avisoAntesDeCancelar(t0),
        contains('pausa de ${SancionConductor.pausa.inMinutes} min'),
      );
      expect(
        con(hace(5, const Duration(hours: 25))).avisoAntesDeCancelar(t0),
        isNull,
      );
    });

    test('fromMap lee lo que escribe la Cloud Function', () {
      final s = SancionConductorRepositoryImpl.fromMap({
        'bloqueadoHasta': Timestamp.fromDate(t0),
        'cancelaciones': [t0.millisecondsSinceEpoch, 'x'],
      });
      expect(s.bloqueadoHasta, t0);
      expect(s.cancelaciones, [t0]);
      expect(
        SancionConductorRepositoryImpl.fromMap(null).bloqueadoHasta,
        isNull,
      );
    });
  });

  group('PausaCancelacionesViewModel', () {
    test('cuenta hacia atrás y se retira sola al llegar a 0', () {
      fakeAsync((async) {
        var ahora = t0;
        final repo = _FakeRepo();
        final vm = PausaCancelacionesViewModel(
          repository: repo,
          conductorId: 'c1',
          now: () => ahora,
        )..iniciar();

        repo.ctrl.add(
          SancionConductor(bloqueadoHasta: t0.add(const Duration(seconds: 3))),
        );
        async.flushMicrotasks();
        expect(vm.enPausa, isTrue);
        expect(vm.textoRestante, '00:03');

        ahora = t0.add(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 1));
        expect(vm.enPausa, isFalse);
        vm.dispose();
      });
    });

    test('al volver a la app con el tiempo cumplido no queda en pausa', () {
      fakeAsync((async) {
        var ahora = t0;
        final repo = _FakeRepo();
        final vm = PausaCancelacionesViewModel(
          repository: repo,
          conductorId: 'c1',
          now: () => ahora,
        )..iniciar();
        repo.ctrl.add(
          SancionConductor(bloqueadoHasta: t0.add(const Duration(minutes: 15))),
        );
        async.flushMicrotasks();
        expect(vm.textoRestante, '15:00');

        ahora = t0.add(const Duration(minutes: 20));
        vm.recalcular();
        expect(vm.enPausa, isFalse);
        vm.dispose();
      });
    });
  });

  testWidgets('modal de pausa y motivos caben en 320 px con texto grande', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Stack(
                children: [
                  Center(
                    child: TextButton(
                      onPressed: () => MotivoCancelacionSheet.mostrar(context),
                      child: const Text('abrir'),
                    ),
                  ),
                  Positioned.fill(
                    child: PausaCancelacionesOverlay(
                      repository: repo,
                      conductorId: 'c1',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Sin pausa no tapa nada: el botón de abajo recibe el toque.
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('El cliente no aparece'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(ListTile, 'Otro motivo')).height,
      greaterThanOrEqualTo(48),
    );
    // Con texto grande la lista scrollea: el último motivo sigue alcanzable.
    await tester.ensureVisible(find.text('Otro motivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otro motivo'));
    await tester.pumpAndSettle();

    repo.ctrl.add(
      SancionConductor(
        bloqueadoHasta: DateTime.now().add(const Duration(minutes: 15)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Pausa por cancelaciones'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Retira el overlay para cortar su Timer.
    await tester.pumpWidget(const SizedBox());
  });
}
