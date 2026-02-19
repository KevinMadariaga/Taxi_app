import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/login_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/registro_cliente_view.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  });
  group('Vistas cliente', () {
    testWidgets('HistorialCliente se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HistorialCliente()));
      expect(find.byType(HistorialCliente), findsOneWidget);
    });
    testWidgets('InicioClienteView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: InicioClienteView()));
      expect(find.byType(InicioClienteView), findsOneWidget);
    });
    testWidgets('Login se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Login()));
      expect(find.byType(Login), findsOneWidget);
    });
    testWidgets('RegistroClienteView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RegistroClienteView()));
      expect(find.byType(RegistroClienteView), findsOneWidget);
    });
  });
}
