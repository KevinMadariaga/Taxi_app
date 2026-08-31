// Antes el campo de comentario de una mala calificación era `maxLines: 1`:
// el texto no envolvía, así que no se podía leer completo ni desplazarse
// dentro de él con el teclado abierto. Estos tests fijan el contrato nuevo:
// multilínea, con tope de caracteres, y sin excepciones cuando el foco
// dispara el scroll-to-field tras el retraso que espera al `Scaffold`
// (mismo molde de verificación que `comentario_sheet_test.dart`, adaptado a
// este widget).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/features/resumen_viaje/widgets/calificacion_section.dart';

void main() {
  /// Monta el widget dentro de un `Scrollable` — igual que en
  /// `resumen_viaje_view.dart` (`SingleChildScrollView`), necesario porque
  /// `_onFocusChange` llama `Scrollable.ensureVisible` sobre el campo.
  Future<void> montar(
    WidgetTester tester, {
    required bool requiereComentario,
    String comentarioInicial = '',
    ValueChanged<String>? onComentarioChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CalificacionSection(
              calificacion: requiereComentario ? 1 : 5,
              onCalificacionChanged: (_) {},
              requiereComentario: requiereComentario,
              comentarioInicial: comentarioInicial,
              onComentarioChanged: onComentarioChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('CalificacionSection — campo de comentario', () {
    testWidgets('con requiereComentario es multilínea, no de una sola línea', (
      tester,
    ) async {
      await montar(tester, requiereComentario: true);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, greaterThan(1));
      expect(field.minLines, isNotNull);
      expect(field.minLines! >= 2, isTrue);
    });

    testWidgets('el texto escrito se conserva completo y se reporta al '
        'callback', (tester) async {
      String? reportado;
      await montar(
        tester,
        requiereComentario: true,
        onComentarioChanged: (v) => reportado = v,
      );
      await tester.pumpAndSettle();

      const texto =
          'El conductor se demoró bastante y el carro llegó sucio por dentro';
      await tester.enterText(find.byType(TextField), texto);
      await tester.pump();

      expect(reportado, texto);
      expect(find.text(texto), findsOneWidget);

      // `enterText` enfoca el campo, lo que dispara el `Future.delayed` de
      // `_scrollCampoTrasTeclado` — hay que dejarlo correr hasta el final
      // antes de que termine el test, si no `flutter_test` falla el test
      // por "A Timer is still pending" al desmontar el árbol con el timer
      // todavía vivo.
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('el comentario se topa en 240 caracteres', (tester) async {
      String? reportado;
      await montar(
        tester,
        requiereComentario: true,
        onComentarioChanged: (v) => reportado = v,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'x' * 300);
      await tester.pump();

      expect(reportado!.length, 240);

      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets(
      'enfocar el campo no lanza excepción tras el scroll-to-field '
      'retrasado',
      (tester) async {
        await montar(tester, requiereComentario: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        // El retraso interno (`_scrollCampoTrasTeclado`) es de 250ms;
        // bombear más que eso para dejarlo correr hasta el final.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sin requiereComentario, el campo no se muestra', (
      tester,
    ) async {
      await montar(tester, requiereComentario: false);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });
}
