import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/complete_profile_page.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

import 'test_helpers/firebase_test_setup.dart';

class _RepoSinUsuario implements ClientAuthRepository {
  @override
  Future<ClientUserEntity?> getClientUserById(String uid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _app(ThemeData Function() theme) {
  final repo = _RepoSinUsuario();
  return MultiProvider(
    providers: [
      Provider(create: (_) => GetClientUserUseCase(repo)),
      Provider(create: (_) => CompleteClientProfileUseCase(repo)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: theme(),
        home: const CompleteProfilePage(uid: 'u1'),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });

  for (final (nombre, tema) in [
    ('claro', () => AppThemeConfig.lightTheme),
    ('oscuro', () => AppThemeConfig.darkTheme),
  ]) {
    for (final tamano in [const Size(360, 640), const Size(800, 1200)]) {
      testWidgets('modo $nombre ${tamano.width.toInt()}px: flujo por pasos', (
        tester,
      ) async {
        tester.view.physicalSize = tamano;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(tema));
        await tester.pumpAndSettle();

        // Paso 1: nombre y apellido.
        expect(find.text('Paso 1 de 3'), findsOneWidget);
        expect(find.text('¿Cómo te llamas?'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Escribe tu nombre.'), findsOneWidget);
        expect(find.text('Escribe tu apellido.'), findsOneWidget);
        expect(find.text('Paso 1 de 3'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'Laura');
        await tester.pumpAndSettle();
        expect(find.text('Escribe tu nombre.'), findsNothing);
        await tester.enterText(find.byType(TextField).at(1), 'Gómez');
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();

        // Paso 2: celular.
        expect(find.text('Paso 2 de 3'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '300123');
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('te faltan 4'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '3001234567');
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();

        // Paso 3: foto obligatoria.
        expect(find.text('Paso 3 de 3'), findsOneWidget);
        await tester.tap(find.text('Crear mi cuenta'));
        await tester.pumpAndSettle();
        expect(find.text('Agrega tu foto de perfil.'), findsOneWidget);

        // Atrás vuelve al paso anterior con los datos intactos.
        await tester.tap(find.byTooltip('Paso anterior'));
        await tester.pumpAndSettle();
        expect(find.text('Paso 2 de 3'), findsOneWidget);
        expect(find.text('3001234567'), findsOneWidget);
      });
    }
  }
}
