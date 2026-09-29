import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/fcm_service.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
    // Sin plugin nativo de FCM en tests: el canal responde vacío.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_messaging'),
          (_) async => null,
        );
  });

  // C3: dos llamadas (aunque la primera siga en curso) comparten la misma
  // inicialización, así que los handlers de FCM no se registran dos veces.
  test('init() llamado dos veces no vuelve a inicializar', () async {
    final primera = FcmService.instance.init();
    final segunda = FcmService.instance.init();
    expect(identical(primera, segunda), isTrue);
    // Puede terminar en error (Auth/Firestore no reales en tests); lo que
    // importa es que fue una sola inicialización.
    await primera.catchError((_) {});
  });
}
