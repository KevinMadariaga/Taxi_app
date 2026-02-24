import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/screens/introductorio_screen.dart';
import 'package:taxi_app/screens/register_screen.dart';
import 'package:taxi_app/screens/splash_screen.dart';

void main() {
  group('Pantallas principales', () {
    testWidgets('HomeView se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HomeView()));
      expect(find.byType(HomeView), findsOneWidget);
    });
    testWidgets('LoginScreen se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: LoginScreen()));
      expect(find.byType(LoginScreen), findsOneWidget);
    });
    testWidgets('RegisterScreen se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RegisterScreen()));
      expect(find.byType(RegisterScreen), findsOneWidget);
    });
    testWidgets('SplashScreen se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(home: SplashScreen(nextScreen: Container())));
      // Verifica inmediatamente después del pump, antes de que navegue
      expect(find.byType(SplashScreen), findsOneWidget);
    });
  });
}
