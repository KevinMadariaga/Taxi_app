import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/screens/perfil/perfil.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });

  for (final (modo, tema) in [
    ('claro', () => AppThemeConfig.lightTheme),
    ('oscuro', () => AppThemeConfig.darkTheme),
  ]) {
    for (final tipo in ['cliente', 'conductor']) {
      testWidgets('perfil $tipo en modo $modo se construye sin overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: tema(),
              home: PaginaPerfilUsuario(tipoUsuario: tipo),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mi perfil'), findsOneWidget);
        expect(find.text('Información del perfil'), findsOneWidget);
        expect(find.text('Editar perfil'), findsNothing);
        expect(find.text('APP'), findsNothing);
        expect(find.byTooltip('Configuración'), findsNothing);
        expect(find.text('Configuración'), findsOneWidget);
        expect(find.byIcon(Icons.photo_camera_rounded), findsNothing);
        expect(
          find.text(
            tipo == 'conductor' ? 'Volver a ser cliente' : 'Ser conductor',
          ),
          findsOneWidget,
        );
        if (tipo == 'conductor') {
          expect(find.text('Membresía inactiva'), findsOneWidget);
        }
      });
    }
  }
}
