import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/widgets/barra_teclado.dart';

void main() {
  testWidgets('con teclado sale "Listo", lo cierra y sube el contenido', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final foco = FocusNode();
    addTearDown(foco.dispose);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: AppThemeConfig.lightTheme,
          builder: (context, child) => BarraTeclado(child: child!),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TextField(focusNode: foco),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Listo'), findsNothing);

    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(foco.hasFocus, isTrue);
    expect(find.text('Listo'), findsOneWidget);
    // El campo quedó por encima de la barra (300 de teclado + 44 de barra).
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(844 - 300 - BarraTeclado.alto),
    );

    await tester.tap(find.text('Listo'));
    await tester.pump();
    expect(foco.hasFocus, isFalse);
  });
}
