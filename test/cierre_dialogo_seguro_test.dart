import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

/// Regresión: cerrar la modal "¿Sigues buscando?" podía llevarse puesta una
/// ruta de PÁGINA en vez del diálogo.
///
/// `_cerrarDialogoOferta` hacía `pop()` sobre el Navigator raíz con un guard
/// `canPop()`, que en Flutter significa solo *"hay ≥2 rutas"* y nunca *"el
/// diálogo está arriba"*. Con la bandera `_modalOfertaAbierto` desincronizada
/// —que es lo que pasa cuando dos cancelaciones caen en el mismo frame— ese
/// `pop` se llevaba la ruta que hubiera encima: `BuscandoTaxiView`, o el
/// `IntermediateTransitionView` recién pusheado. Con la pila ya vaciada por un
/// `clearStackOnNext`, eso deja al Navigator sin rutas y Flutter cierra la app.
///
/// El reemplazo es `cerrarRutasSobre`, que cierra todo lo que esté por encima
/// de la ruta propia y se detiene ahí (o en la raíz, como red de seguridad).
///
/// Se ejercita la función REAL de producción, no una copia del predicado: un
/// test que reimplementa la lógica sigue en verde aunque alguien vuelva a
/// poner el `pop()` ciego en la app.
void main() {
  late NavigatorState nav;
  // El context de la ruta "propia": la pantalla desde la que se cierra.
  late BuildContext ctxPropio;

  Widget montar() => MaterialApp(
    home: Builder(
      builder: (ctx) {
        nav = Navigator.of(ctx);
        ctxPropio = ctx;
        return const Scaffold(body: Text('pagina-1'));
      },
    ),
  );

  Future<void> pushPagina(WidgetTester tester, String texto) async {
    nav.push(
      MaterialPageRoute<void>(
        builder: (ctx) {
          ctxPropio = ctx;
          return Scaffold(body: Text(texto));
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirDialogo(WidgetTester tester) async {
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(title: Text('¿Sigues buscando?')),
    );
    await tester.pumpAndSettle();
  }

  void cerrarDialogo() => cerrarRutasSobre(ctxPropio);

  testWidgets('quita el diálogo y deja la página debajo', (tester) async {
    await tester.pumpWidget(montar());
    await pushPagina(tester, 'buscando');
    await abrirDialogo(tester);
    expect(find.text('¿Sigues buscando?'), findsOneWidget);

    cerrarDialogo();
    await tester.pumpAndSettle();

    expect(find.text('¿Sigues buscando?'), findsNothing);
    expect(find.text('buscando'), findsOneWidget);
  });

  testWidgets('sin diálogo abierto NO toca la pila', (tester) async {
    // Este es el caso que rompía: la bandera decía "hay diálogo" pero ya no
    // había ninguno, y el `pop()` se llevaba la página.
    await tester.pumpWidget(montar());
    await pushPagina(tester, 'buscando');
    expect(find.text('buscando'), findsOneWidget);

    cerrarDialogo();
    await tester.pumpAndSettle();

    expect(find.text('buscando'), findsOneWidget);
  });

  testWidgets('con una sola ruta tampoco la popea', (tester) async {
    // El escenario terminal: después de `clearStackOnNext` queda una sola
    // ruta. Un `pop()` acá deja el Navigator vacío y la app se cierra.
    await tester.pumpWidget(montar());
    expect(find.text('pagina-1'), findsOneWidget);

    cerrarDialogo();
    await tester.pumpAndSettle();

    expect(find.text('pagina-1'), findsOneWidget);
  });

  testWidgets('también cierra una PÁGINA pusheada encima', (tester) async {
    // `EditarOfertaBusquedaView` se pushea como MaterialPageRoute, no como
    // diálogo: el predicado viejo (`route is! PopupRoute`) se detenía en ella
    // y la dejaba arriba, así que el `pushReplacement` de la navegación se la
    // comía y `BuscandoTaxiView` quedaba viva debajo.
    await tester.pumpWidget(montar());
    await pushPagina(tester, 'buscando');
    final ctxBuscando = ctxPropio;
    await pushPagina(tester, 'editar-oferta');
    expect(find.text('editar-oferta'), findsOneWidget);

    cerrarRutasSobre(ctxBuscando);
    await tester.pumpAndSettle();

    expect(find.text('editar-oferta'), findsNothing);
    expect(find.text('buscando'), findsOneWidget);
  });

  testWidgets('quita varios diálogos apilados de una', (tester) async {
    await tester.pumpWidget(montar());
    await pushPagina(tester, 'buscando');
    await abrirDialogo(tester);
    showDialog<void>(
      context: nav.context,
      builder: (_) => const AlertDialog(title: Text('otro')),
    );
    await tester.pumpAndSettle();

    cerrarDialogo();
    await tester.pumpAndSettle();

    expect(find.text('otro'), findsNothing);
    expect(find.text('¿Sigues buscando?'), findsNothing);
    expect(find.text('buscando'), findsOneWidget);
  });
}
