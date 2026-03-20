import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/historial_viaje_conductor.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/login_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/registro_conductor_view.dart';
import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });
  group('Vistas conductor', () {
    testWidgets('HistorialConductor se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HistorialConductor()));
      expect(find.byType(HistorialConductor), findsOneWidget);
    });
    testWidgets('HomeConductorMapView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: InicioConductor()));
      expect(find.byType(InicioConductor), findsOneWidget);
    });
    testWidgets('LoginConductorView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: LoginConductorView()));
      expect(find.byType(LoginConductorView), findsOneWidget);
    });
    testWidgets('RegistroConductorView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RegistroConductorView()));
      expect(find.byType(RegistroConductorView), findsOneWidget);
    });
  });
}
