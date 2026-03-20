import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/registro_cliente_view.dart';
import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });
  group('Vistas cliente', () {
    testWidgets('HistorialCliente se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HistorialCliente()));
      expect(find.byType(HistorialCliente), findsOneWidget);
    });
    testWidgets('InicioClienteView se puede construir', (tester) async {
      tester.view.physicalSize = const Size(1440, 2960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(home: InicioClienteView()));
      expect(find.byType(InicioClienteView), findsOneWidget);
    });
    testWidgets('RegistroClienteView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RegistroClienteView()));
      expect(find.byType(RegistroClienteView), findsOneWidget);
    });
  });
}
