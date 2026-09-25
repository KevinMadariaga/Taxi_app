import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/features/admin/admin_configuracion_screen.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';
import 'package:taxi_app/widgets/dialogo_dias_membresia.dart';

import 'test_helpers/firebase_test_setup.dart';

Future<void> _montar(
  WidgetTester tester,
  ThemeData Function() tema,
  Widget home, {
  bool esperar = true,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(theme: tema(), home: home),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });

  for (final (modo, tema) in [
    ('claro', () => AppThemeConfig.lightTheme),
    ('oscuro', () => AppThemeConfig.darkTheme),
  ]) {
    testWidgets('confirmación devuelve la elección ($modo)', (tester) async {
      bool? resultado;
      await _montar(
        tester,
        tema,
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => resultado = await mostrarConfirmacion(
                ctx,
                titulo: 'Revocar membresía',
                mensaje: 'Se desactivará el servicio de Laura.',
                accion: 'Revocar',
                peligro: true,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Revocar membresía'), findsOneWidget);
      await tester.tap(find.text('Revocar'));
      await tester.pumpAndSettle();
      expect(resultado, isTrue);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resultado, isFalse);
    });

    testWidgets('días de membresía: cuadros y aprobar ($modo)', (tester) async {
      int? dias;
      await _montar(
        tester,
        tema,
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  dias = await mostrarDialogoDiasMembresia(ctx),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      for (final d in ['7', '15', '30', '60', '90']) {
        expect(find.text(d), findsWidgets);
      }
      await tester.tap(find.text('60'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();
      expect(dias, 60);
    });

    testWidgets('gestión con pestañas ($modo)', (tester) async {
      await _montar(tester, tema, const AdminHubScreen(), esperar: false);
      expect(find.text('Gestión'), findsOneWidget);
      expect(find.text('Reportes'), findsOneWidget);
      expect(find.text('Mensajes'), findsOneWidget);
      expect(find.text('Sugerencias'), findsOneWidget);
    });

    testWidgets('configuración del admin ($modo)', (tester) async {
      await _montar(
        tester,
        tema,
        const AdminConfiguracionScreen(adminId: 'a1'),
        esperar: false,
      );
      expect(find.text('Configuración'), findsOneWidget);
    });
  }
}
