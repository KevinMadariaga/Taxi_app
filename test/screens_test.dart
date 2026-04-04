import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/screens/introductorio_screen.dart';
import 'test_helpers/firebase_test_setup.dart';
import 'test_helpers/widget_test_wrapper.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });
  group('Pantallas principales', () {
    testWidgets('HomeView se puede construir', (tester) async {
      await tester.pumpWidget(buildTestAppFor(HomeView()));
      expect(find.byType(HomeView), findsOneWidget);
    });
    testWidgets('LoginScreen se puede construir', (tester) async {
      await tester.pumpWidget(buildTestAppFor(LoginScreen()));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    // testWidgets('SplashScreen se puede construir', (tester) async {
    //   await tester.pumpWidget(MaterialApp(home: SplashScreen(nextScreen: Container())));
    //   // Verifica inmediatamente después del pump, antes de que navegue
    //   expect(find.byType(SplashScreen), findsOneWidget);
    // });
  });
}
