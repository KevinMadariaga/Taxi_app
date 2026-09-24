// Regresión capturada en dispositivo real (Android 13 y iPhone iOS 26, el
// mismo fallo en ambos): al cerrar el sheet de comentario se lanzaba
//
//   A TextEditingController was used after being disposed.
//
// seguido de "A RenderFlex overflowed by ~99.600 pixels on the bottom" y de
// "'_dependents.isEmpty': is not true".
//
// Causa: el controller se creaba antes de `showModalBottomSheet` y se disponía
// en la línea siguiente al `await`. Ese `await` completa al hacer pop, pero el
// sheet sigue animando su salida y se reconstruye durante la transición — el
// `TextField` volvía a usar el controller ya disposed.
//
// Estos tests bombean la animación de cierre COMPLETA (`pumpAndSettle`) después
// del pop, que es justo la ventana donde reventaba: con el código anterior
// fallan; con el sheet como StatefulWidget dueño del controller, pasan.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/viewmodels/confirmar_solicitud_viewmodel.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/vistas/widgets/comentario_sheet.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/vistas/widgets/metodo_pago_sheet.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/vistas/widgets/tipo_vehiculo_sheet.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    // El VM construye repositorios reales por defecto (Firestore).
    await setupFirebaseForTests();
  });

  const punto = LocationModel(position: LatLng(8.24, -73.35));

  ConfirmarSolicitudViewModel buildVm() =>
      ConfirmarSolicitudViewModel(origenInicial: punto, destinoInicial: punto);

  /// Monta una pantalla con un botón que abre el sheet, igual que la vista real.
  Future<void> montar(WidgetTester tester, ConfirmarSolicitudViewModel vm) {
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => mostrarComentarioSheet(ctx, vm),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('mostrarComentarioSheet', () {
    testWidgets('cerrar con el botón Guardar no usa el controller disposed', (
      tester,
    ) async {
      final vm = buildVm();
      addTearDown(vm.dispose);
      await montar(tester, vm);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'portón blanco');
      await tester.pump();

      await tester.tap(find.text('Guardar nota'));
      // La animación de salida completa: acá es donde el sheet se reconstruía
      // con el controller ya disposed.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(vm.comentario, 'portón blanco');
    });

    testWidgets('descartar con el botón atrás tampoco lanza', (tester) async {
      final vm = buildVm();
      addTearDown(vm.dispose);
      await montar(tester, vm);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'algo sin guardar');
      await tester.pump();

      // Cierre por gesto/atrás, sin pasar por "Guardar comentario".
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Descartado: no se guardó nada.
      expect(vm.comentario, isEmpty);
    });

    testWidgets('abrir y cerrar varias veces no acumula fallos', (
      tester,
    ) async {
      final vm = buildVm();
      addTearDown(vm.dispose);
      await montar(tester, vm);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'intento $i');
        await tester.pump();
        await tester.tap(find.text('Guardar nota'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(vm.comentario, 'intento 2');
      // El sheet reabierto arranca con el comentario ya guardado.
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('intento 2'), findsOneWidget);
    });

    testWidgets('las sugerencias rellenan el campo y se guardan', (
      tester,
    ) async {
      final vm = buildVm();
      addTearDown(vm.dispose);
      await montar(tester, vm);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Llevo mascota'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(vm.comentario, 'Llevo mascota');
    });

    testWidgets('el comentario se topa en 140 caracteres', (tester) async {
      final vm = buildVm();
      addTearDown(vm.dispose);
      await montar(tester, vm);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'x' * 300);
      await tester.pump();
      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();

      expect(vm.comentario.length, 140);
    });
  });

  testWidgets('método de pago: elegir Nequi lo guarda y cierra la hoja', (
    tester,
  ) async {
    final vm = buildVm();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => mostrarMetodoPagoSheet(ctx, vm),
              child: const Text('pago'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pago'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo vas a pagar?'), findsOneWidget);

    await tester.tap(find.text('Nequi'));
    await tester.pumpAndSettle();
    expect(vm.metodoPago, 'Nequi');
    expect(find.text('¿Cómo vas a pagar?'), findsNothing);
  });

  testWidgets('tipo de vehículo: valida el valor y confirma la elección', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final vm = buildVm();
    addTearDown(vm.dispose);
    bool? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async =>
                  resultado = await mostrarTipoVehiculoSheet(ctx, vm),
              child: const Text('vehiculo'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('vehiculo'));
    await tester.pumpAndSettle();
    expect(find.text('Elige tu vehículo'), findsOneWidget);

    await tester.tap(find.text('Moto'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    // Valor vacío: error en línea, la hoja sigue abierta.
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Confirmar vehículo'));
    await tester.pumpAndSettle();
    expect(find.text('Elige tu vehículo'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), '9000');
    await tester.tap(find.text('Confirmar vehículo'));
    await tester.pumpAndSettle();
    expect(resultado, isTrue);
    expect(vm.tipoVehiculo, VehicleType.moto);
  });
}
