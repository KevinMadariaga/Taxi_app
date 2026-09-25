import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';

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

  test('caracteristicas no importa screens/ (navega por RutasApp)', () {
    expect(importsProhibidos('lib/caracteristicas', 'screens/'), isEmpty);
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

  group('rutas con nombre que usa caracteristicas/', () {
    late BuildContext ctx;
    Widget construir(String nombre, Map<String, dynamic> args) =>
        (AppRoutes.onGenerateRoute(RouteSettings(name: nombre, arguments: args))
                as MaterialPageRoute)
            .builder(ctx);

    testWidgets('clienteInicio, resumenes y buscandoTaxi reciben sus args', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      ctx = tester.element(find.byType(SizedBox));

      expect(
        (construir(RutasApp.clienteInicio, {'authUid': 'u1'})
                as HomeClienteView)
            .authUid,
        'u1',
      );
      expect(
        (construir(RutasApp.resumenCliente, {'solicitudId': 's1'})
                as ResumenClienteView)
            .solicitudId,
        's1',
      );
      expect(
        (construir(RutasApp.resumenConductor, {'solicitudId': 's2'})
                as ResumenConductorView)
            .solicitudId,
        's2',
      );
      final buscando =
          construir(RutasApp.buscandoTaxi, {
                'solicitudId': 's3',
                'initialClientLocation': const LatLng(8.2, -73.3),
              })
              as BuscandoTaxiView;
      expect(buscando.solicitudId, 's3');
      expect(buscando.initialClientLocation, const LatLng(8.2, -73.3));
    });

    test('clienteInicio tras login conserva la transición de entrada', () {
      final ruta = AppRoutes.onGenerateRoute(
        const RouteSettings(
          name: RutasApp.clienteInicio,
          arguments: {'transicionInicio': true},
        ),
      );
      expect(ruta, isA<PageRouteBuilder>());
    });
  });
}
