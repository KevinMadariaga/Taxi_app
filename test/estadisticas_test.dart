import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/estadisticas/dominio/entidades/estadistica_dia.dart';
import 'package:taxi_app/caracteristicas/estadisticas/dominio/repositorios/estadisticas_repository.dart';
import 'package:taxi_app/caracteristicas/estadisticas/presentacion/vistas/estadisticas_admin_screen.dart';
import 'package:taxi_app/caracteristicas/estadisticas/presentacion/widgets/graficas.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

class _RepoFalso implements EstadisticasRepository {
  _RepoFalso(this.datos);

  final List<EstadisticaDia> datos;

  @override
  Stream<List<EstadisticaDia>> watchUltimosDias(int dias) =>
      Stream.value(completarDias(datos, hoy: hoyColombia(), n: dias));
}

void main() {
  test('hoy en Colombia: las 11 pm del 12 siguen siendo el 12', () {
    // 2026-10-13 04:30 UTC = 2026-10-12 23:30 en Colombia.
    expect(
      hoyColombia(DateTime.utc(2026, 10, 13, 4, 30)),
      DateTime(2026, 10, 12),
    );
    expect(claveDia(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('completarDias rellena con ceros y deja el más viejo primero', () {
    final hoy = DateTime(2026, 10, 12);
    final dias = completarDias(
      [EstadisticaDia(dia: DateTime(2026, 10, 10), creadas: 4)],
      hoy: hoy,
      n: 3,
    );
    expect(dias.map((d) => d.dia.day), [10, 11, 12]);
    expect(dias.map((d) => d.creadas), [4, 0, 0]);
  });

  test('en curso y tasa de completado', () {
    final d = EstadisticaDia(
      dia: DateTime(2026),
      creadas: 10,
      completadas: 6,
      canceladas: 2,
      sinRespuesta: 1,
    );
    expect(d.enCurso, 1);
    expect(d.tasaCompletado, 0.6);
  });

  test('tope redondo del eje', () {
    expect(topeRedondo(0), 4);
    expect(topeRedondo(7), 10);
    expect(topeRedondo(13), 20);
    expect(topeRedondo(48), 50);
    expect(topeRedondo(120), 200);
  });

  for (final ancho in [320.0, 390.0, 1200.0]) {
    testWidgets('panel de estadísticas sin desbordes a ${ancho.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(ancho, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hoy = hoyColombia();
      final repo = _RepoFalso([
        EstadisticaDia(
          dia: hoy,
          creadas: 12,
          completadas: 7,
          canceladas: 3,
          sinRespuesta: 1,
          clientesUnicos: 9,
          porHora: [for (var h = 0; h < 24; h++) h % 5],
        ),
        EstadisticaDia(
          dia: DateTime(hoy.year, hoy.month, hoy.day - 1),
          creadas: 5,
          completadas: 5,
        ),
      ]);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppThemeConfig.lightTheme,
            home: EstadisticasAdminScreen(repositorio: repo),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Hoy'), findsWidgets);
      expect(find.text('12'), findsWidgets); // creadas hoy
      expect(find.text('58%'), findsOneWidget); // 7 de 12
      expect(find.text('Completadas'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Tocar el día anterior lo elige.
      await tester.tap(find.bySemanticsLabel(RegExp(r': 5 creadas')).first);
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
