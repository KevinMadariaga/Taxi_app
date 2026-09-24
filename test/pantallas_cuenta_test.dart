import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/core/theme/theme_controller.dart';
import 'package:taxi_app/screens/perfil/editar_perfil.dart';
import 'package:taxi_app/screens/perfil/informacion_perfil_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/configuracion_aplicacion_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/notificaciones_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/seguridad_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/ayuda_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/completar_registro_conductor_view.dart';

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
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(theme: tema(), home: home),
      ),
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
    testWidgets('configuración ($modo)', (tester) async {
      await _montar(tester, tema, const ConfiguracionAplicacionView());
      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Apariencia'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('Eliminar cuenta'), findsOneWidget);
    });

    testWidgets('editar perfil conductor ($modo)', (tester) async {
      TextEditingController c(String t) => TextEditingController(text: t);
      await _montar(
        tester,
        tema,
        EditarPerfilScreen(
          nombreController: c('Laura'),
          apellidoController: c('Gómez'),
          telefonoController: c('3001234567'),
          placaController: c('ABC123'),
          esConductor: true,
          onImageChanged: (_) async {},
          onVehicleImageChanged: (_) async {},
          onSave: (_) async {},
        ),
      );
      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.text('DATOS PERSONALES'), findsOneWidget);
      expect(find.text('VEHÍCULO'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
      // Título centrado en la AppBar neutra.
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isTrue);
    });

    testWidgets('ayuda conductor con búsqueda ($modo)', (tester) async {
      await _montar(tester, tema, const AyudaConductorView());
      expect(find.text('¿En qué te ayudamos?'), findsOneWidget);
      expect(find.text('¿Cómo acepto una solicitud de viaje?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'vehículo');
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo acepto una solicitud de viaje?'), findsNothing);
      expect(
        find.text('¿Cómo actualizo los datos de mi vehículo?'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No encontramos esa pregunta.'), findsOneWidget);
    });

    testWidgets('soporte y seguridad ($modo)', (tester) async {
      await _montar(tester, tema, const SoporteView());
      expect(find.text('Chat en vivo'), findsOneWidget);
      expect(find.text('Preguntas frecuentes'), findsOneWidget);

      await _montar(tester, tema, const SeguridadView());
      expect(find.text('Contactos de emergencia'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
    });

    testWidgets('notificaciones ($modo)', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_noti_promos': true});
      await _montar(tester, tema, const NotificacionesView(), esperar: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Notificaciones'), findsOneWidget);
    });

    // Carga sus datos de Firestore, que en tests no responde: se verifica
    // el estado de carga (AppBar neutra + spinner).
    testWidgets('información del perfil cargando ($modo)', (tester) async {
      await _montar(
        tester,
        tema,
        InformacionPerfilView(uid: 'u1', esConductor: true, onEditar: () {}),
        esperar: false,
      );
      expect(find.text('Información del perfil'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('registro conductor valida en línea ($modo)', (tester) async {
      await _montar(tester, tema, const CompletarRegistroConductorView());
      expect(find.text('Registra tu vehículo'), findsOneWidget);

      await tester.tap(find.text('Enviar registro'));
      await tester.pumpAndSettle();
      expect(find.text('Agrega la foto de tu vehículo.'), findsOneWidget);
      expect(find.text('Escribe la placa de tu vehículo.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abc-12');
      await tester.pumpAndSettle();
      expect(find.text('ABC12'), findsOneWidget);
      expect(find.text('Escribe la placa de tu vehículo.'), findsNothing);
    });
  }
}
