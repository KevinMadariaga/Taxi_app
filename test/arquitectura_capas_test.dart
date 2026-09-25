import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';

/// Imports de [carpeta] que cumplen [patron] (relativo a `package:taxi_app/`).
List<String> importsProhibidos(String carpeta, String patron) {
  final prohibido = RegExp(
    "^import 'package:taxi_app/$patron",
    multiLine: true,
  );
  final violaciones = <String>[];
  for (final f in Directory(carpeta).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final m in prohibido.allMatches(f.readAsStringSync())) {
      violaciones.add('${f.path}: ${m.group(0)}');
    }
  }
  return violaciones;
}

void main() {
  test('core no importa capas superiores (pantallas, features, rutas)', () {
    expect(
      importsProhibidos(
        'lib/core',
        '(caracteristicas|features|screens|presentation|routes|widgets)/',
      ),
      isEmpty,
    );
  });

  test('widgets globales no dependen de pantallas legacy', () {
    expect(importsProhibidos('lib/widgets', 'screens/'), isEmpty);
  });

  test('caracteristicas no toma modelos ni viewmodels de screens/', () {
    expect(
      importsProhibidos(
        'lib/caracteristicas',
        r'screens/[^\x27]*/(model|viewmodels)/',
      ),
      isEmpty,
    );
  });

  group('rutas con nombre que usa FcmService', () {
    testWidgets('adminHub abre AdminHubScreen en la pestaña pedida', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final ctx = tester.element(find.byType(SizedBox));

      final ruta =
          AppRoutes.onGenerateRoute(
                const RouteSettings(
                  name: RutasApp.adminHub,
                  arguments: {'initialTab': 2},
                ),
              )
              as MaterialPageRoute;

      expect(ruta.settings.name, RutasApp.adminHub);
      expect((ruta.builder(ctx) as AdminHubScreen).initialTab, 2);
    });

    testWidgets('conductorInicio pasa mostrarBienvenida', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final ctx = tester.element(find.byType(SizedBox));

      final ruta =
          AppRoutes.onGenerateRoute(
                const RouteSettings(
                  name: RutasApp.conductorInicio,
                  arguments: {'mostrarBienvenida': true},
                ),
              )
              as MaterialPageRoute;

      expect(ruta.settings.name, RutasApp.conductorInicio);
      expect((ruta.builder(ctx) as InicioConductor).mostrarBienvenida, isTrue);
    });
  });
}
