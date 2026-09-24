import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/vistas/widgets/ruta_paradas_card.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

void main() {
  for (final (modo, paleta) in [
    ('claro', AppPalette.light),
    ('oscuro', AppPalette.dark),
  ]) {
    testWidgets('recorrido ($modo): muestra paradas y cada una es editable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var origen = 0, destino = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [paleta]),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RutaParadasCard(
                origen: 'Calle 10 # 4-25, barrio muy largo que no cabe',
                destino: 'Terminal de transportes',
                onEditarOrigen: () => origen++,
                onEditarDestino: () => destino++,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Recogida'), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      await tester.tap(find.text('Terminal de transportes'));
      await tester.tap(find.text('Recogida'));
      expect(origen, 1);
      expect(destino, 1);
    });
  }
}
