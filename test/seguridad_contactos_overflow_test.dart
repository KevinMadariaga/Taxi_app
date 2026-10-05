import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/seguridad_view.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(setupFirebaseForTests);

  // Regresión: "A RenderFlex overflowed by 42 pixels" al agregar el 5.º
  // contacto. Un desborde de layout hace fallar el test por sí solo.
  for (final tamano in const [Size(360, 640), Size(390, 844)]) {
    testWidgets('5 contactos caben en el panel (${tamano.width.toInt()}×'
        '${tamano.height.toInt()})', (tester) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppThemeConfig.lightTheme,
            home: const SeguridadView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contactos de emergencia').first);
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.textContaining('Agregar contacto'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Contacto $i');
        await tester.enterText(find.byType(TextFormField).at(1), '300123456$i');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
      }

      // El teclado del formulario todavía cerrándose (lo que pasaba en el
      // teléfono al guardar el 5.º): el panel no debe desbordarse.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(find.textContaining('5/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
