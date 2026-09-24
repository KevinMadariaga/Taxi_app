import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/cambiar_oferta_dialog.dart';

/// Diálogo "¿Sigues buscando?" — sale cada 5 min de búsqueda sin conductor.
///
/// Se monta desde un botón (y no con `showDialog` suelto) para tener un
/// context por debajo del `Navigator`, y se hace `pumpAndSettle()` después
/// del pop para cubrir la animación de salida y el dispose del controller —
/// mismo molde que `comentario_sheet_test.dart`.
void main() {
  late double? resultado;
  late bool cerrado;

  Widget montar({String? Function(String digits)? validar}) {
    resultado = null;
    cerrado = false;
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                resultado = await mostrarCambiarOfertaDialog(
                  ctx,
                  valorActual: 11000,
                  validar: validar ?? (_) => null,
                );
                cerrado = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> abrir(WidgetTester tester) async {
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('precarga el valor actual formateado', (tester) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    expect(find.text('11.000'), findsOneWidget);
    expect(find.text('¿Sigues buscando?'), findsOneWidget);
  });

  testWidgets('los botones van apilados y con la etiqueta entera', (
    tester,
  ) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    final continuar = find.text('Continuar buscando');
    final cambiar = find.text('Cambiar oferta');
    expect(continuar, findsOneWidget);
    expect(cambiar, findsOneWidget);

    // Apilados: mismo eje horizontal, la acción propuesta arriba.
    final arriba = tester.getCenter(cambiar);
    final abajo = tester.getCenter(continuar);
    expect(arriba.dx, moreOrLessEquals(abajo.dx, epsilon: 1));
    expect(arriba.dy, lessThan(abajo.dy));

    // Ninguna etiqueta queda cortada. `find.text` matchea el String aunque
    // se pinte con ellipsis, así que lo que se compara son los anchos ya
    // maquetados: si las dos estuvieran recortadas a la misma caja medirían
    // igual. "Continuar buscando" tiene que medir MÁS que "Cambiar oferta".
    final anchoLargo = tester.getSize(continuar).width;
    final anchoCorto = tester.getSize(cambiar).width;
    expect(anchoLargo, greaterThan(anchoCorto));
  });

  testWidgets('los textos van centrados', (tester) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    TextAlign? alineacionDe(String texto) =>
        tester.widget<Text>(find.text(texto)).textAlign;

    expect(alineacionDe('¿Sigues buscando?'), TextAlign.center);
    expect(alineacionDe('Aún no encontramos un conductor.'), TextAlign.center);
    expect(alineacionDe('Valor del servicio'), TextAlign.center);
    expect(
      tester.widget<TextField>(find.byType(TextField)).textAlign,
      TextAlign.center,
    );
  });

  testWidgets('"Continuar buscando" cierra sin valor', (tester) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    await tester.tap(find.text('Continuar buscando'));
    await tester.pumpAndSettle();

    expect(cerrado, isTrue);
    expect(resultado, isNull);
  });

  testWidgets('"Cambiar oferta" devuelve el valor escrito', (tester) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    await tester.enterText(find.byType(TextField), '15000');
    await tester.pump();
    // Se reformatea con separador de miles mientras se escribe.
    expect(find.text('15.000'), findsOneWidget);

    await tester.tap(find.text('Cambiar oferta'));
    await tester.pumpAndSettle();

    expect(resultado, 15000);
  });

  testWidgets('un valor inválido pinta el error y NO cierra', (tester) async {
    await tester.pumpWidget(
      montar(validar: (digits) => digits == '100' ? 'Muy bajo.' : null),
    );
    await abrir(tester);

    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Cambiar oferta'));
    await tester.pumpAndSettle();

    expect(find.text('Muy bajo.'), findsOneWidget);
    expect(cerrado, isFalse);
    expect(find.text('¿Sigues buscando?'), findsOneWidget);

    // Y escribir de nuevo limpia el error.
    await tester.enterText(find.byType(TextField), '15000');
    await tester.pumpAndSettle();
    expect(find.text('Muy bajo.'), findsNothing);
  });

  testWidgets('no se descarta tocando fuera del diálogo', (tester) async {
    await tester.pumpWidget(montar());
    await abrir(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(cerrado, isFalse);
    expect(find.text('¿Sigues buscando?'), findsOneWidget);
  });
}
