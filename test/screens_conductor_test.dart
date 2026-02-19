import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/historial_viaje_conductor.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/login_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/registro_conductor_view.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  });
  group('Vistas conductor', () {
    testWidgets('HistorialConductor se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HistorialConductor()));
      expect(find.byType(HistorialConductor), findsOneWidget);
    });
    testWidgets('HomeConductorMapView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HomeConductorMapView()));
      expect(find.byType(HomeConductorMapView), findsOneWidget);
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
