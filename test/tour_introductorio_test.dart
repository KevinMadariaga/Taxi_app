import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/tour_introductorio/dominio/tour_repository.dart';
import 'package:taxi_app/caracteristicas/tour_introductorio/presentacion/paso_tour.dart';
import 'package:taxi_app/caracteristicas/tour_introductorio/presentacion/tour_introductorio.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

class _RepoEnMemoria implements TourRepository {
  final vistos = <String>{};

  @override
  Future<bool> yaVisto(String tourId, String uid) async =>
      vistos.contains('$tourId/$uid');

  @override
  Future<void> marcarVisto(String tourId, String uid) async =>
      vistos.add('$tourId/$uid');
}

final _a = GlobalKey();
final _b = GlobalKey();
final _c = GlobalKey();
final _sinMontar = GlobalKey();

List<PasoTour> _pasos() => [
  PasoTour(
    objetivo: _a,
    icono: Icons.search,
    titulo: 'Paso A',
    descripcion: 'Uno',
  ),
  PasoTour(
    objetivo: _sinMontar,
    icono: Icons.block,
    titulo: 'Paso fantasma',
    descripcion: 'No está en pantalla',
  ),
  PasoTour(
    objetivo: _b,
    icono: Icons.star,
    titulo: 'Paso B',
    descripcion: 'Dos',
  ),
  PasoTour(
    objetivo: _c,
    icono: Icons.menu,
    titulo: 'Paso C',
    descripcion: 'Tres',
  ),
];

Future<void> _montar(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) alAbrir,
  bool sinAnimaciones = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: AppThemeConfig.lightTheme,
        // MaterialApp arma su propio MediaQuery: se ajusta acá encima.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: sinAnimaciones),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                SizedBox(key: _a, height: 60, width: 300),
                const SizedBox(height: 200),
                SizedBox(key: _b, height: 60, width: 300),
                const Spacer(),
                SizedBox(key: _c, height: 60, width: 390),
                TextButton(
                  onPressed: () => alAbrir(context),
                  child: const Text('abrir'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  // El anillo late en bucle: pumpAndSettle no terminaría nunca.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Deja terminar la transición entre pasos (el anillo late en bucle, así que
/// pumpAndSettle no sirve).
Future<void> _avanzar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('avanza, retrocede y termina; omite pasos sin elemento', (
    tester,
  ) async {
    await _montar(
      tester,
      alAbrir: (c) => mostrarTourIntroductorio(c, _pasos()),
    );

    expect(find.text('Paso A'), findsOneWidget);
    expect(find.text('Atrás'), findsNothing);

    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    expect(find.text('Paso B'), findsOneWidget);
    expect(find.text('Paso fantasma'), findsNothing);

    await tester.tap(find.text('Atrás'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    expect(find.text('Paso C'), findsOneWidget);
    expect(find.text('¡Listo!'), findsOneWidget);

    await tester.tap(find.text('¡Listo!'));
    await _avanzar(tester);
    expect(find.text('Paso C'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saltar cierra el recorrido', (tester) async {
    await _montar(
      tester,
      alAbrir: (c) => mostrarTourIntroductorio(c, _pasos()),
    );
    await tester.tap(find.text('Saltar'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsNothing);
  });

  testWidgets('sale solo la primera vez por usuario', (tester) async {
    final repo = _RepoEnMemoria();
    Future<void> abrir(BuildContext c) => mostrarTourSiEsPrimeraVez(
      c,
      tourId: 'inicio',
      uid: 'u1',
      pasos: _pasos(),
      repositorio: repo,
    );

    await _montar(tester, alAbrir: abrir);
    expect(find.text('Paso A'), findsOneWidget);
    await tester.tap(find.text('Saltar'));
    await _avanzar(tester);

    await tester.tap(find.text('abrir'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsNothing);
  });

  testWidgets('con animaciones reducidas funciona sin animar', (tester) async {
    await _montar(
      tester,
      sinAnimaciones: true,
      alAbrir: (c) => mostrarTourIntroductorio(c, _pasos()),
    );
    expect(find.text('Paso A'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Paso B'), findsOneWidget);
  });
}
