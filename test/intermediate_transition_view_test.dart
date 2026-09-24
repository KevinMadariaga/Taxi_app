import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

/// Regresión: al cancelarse la búsqueda por inactividad, la app se iba al
/// escritorio en vez de volver al inicio.
///
/// El mecanismo: `navigateWithIntermediateLoader(clearStackOnNext: true)`
/// termina con `pushAndRemoveUntil(..., (route) => false)`, o sea que esta
/// pantalla puede quedar como ÚNICA ruta del Navigator. En Flutter, una sola
/// ruta sin `PopScope` da `popDisposition == bubble` → `maybePop()` devuelve
/// `false` → el framework llama a `SystemNavigator.pop()` y cierra la app.
///
/// Con `PopScope(canPop: false)` el back se absorbe y la app sigue viva.
///
/// NOTA: nada de `pumpAndSettle` acá. Esta pantalla tiene una animación en
/// bucle (`_ripple.repeat()`), así que nunca queda quieta: `pumpAndSettle`
/// bombea hasta su timeout, dispara el timer de navegación y te deja mirando
/// la pantalla siguiente.
void main() {
  Widget montar({required Duration delay}) => MaterialApp(
    home: IntermediateTransitionView(
      nextBuilder: (_) => const Scaffold(body: Text('siguiente')),
      delay: delay,
      title: 'Búsqueda cancelada',
      subtitle: 'Se canceló tu solicitud automáticamente por inactividad.',
      icon: Icons.timer_off_rounded,
      drawCheck: false,
    ),
  );

  testWidgets('siendo la única ruta, el back NO la popea', (tester) async {
    // Delay largo: lo que se prueba es la ventana ANTES de que navegue sola.
    await tester.pumpWidget(montar(delay: const Duration(seconds: 30)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Búsqueda cancelada'), findsOneWidget);

    // `handlePopRoute` es exactamente lo que dispara el back de Android. Si
    // devuelve false, `WidgetsBinding` llama a `SystemNavigator.pop()` y la
    // app se cierra.
    final manejado = await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    expect(manejado, isTrue, reason: 'sin esto la app se cierra al escritorio');
    expect(find.text('Búsqueda cancelada'), findsOneWidget);
    expect(find.text('siguiente'), findsNothing);
  });

  testWidgets('con clearStackOnNext queda sola y el back no cierra', (
    tester,
  ) async {
    // La rama del bug reportado: `pushAndRemoveUntil((route) => false)` deja
    // UNA sola ruta. Antes, durante esa ventana, el back cerraba la app.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => navigateWithIntermediateLoader(
              context: ctx,
              nextBuilder: (_) => const Scaffold(body: Text('inicio')),
              delay: const Duration(seconds: 30),
              title: 'Búsqueda cancelada',
              subtitle: 'Se canceló por inactividad.',
              icon: Icons.timer_off_rounded,
              drawCheck: false,
              clearStackOnNext: true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Búsqueda cancelada'), findsOneWidget);

    final manejado = await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    expect(manejado, isTrue, reason: 'sin esto la app se cierra al escritorio');
    expect(find.text('Búsqueda cancelada'), findsOneWidget);
  });

  testWidgets('sigue navegando sola al terminar el delay', (tester) async {
    await tester.pumpWidget(montar(delay: const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Búsqueda cancelada'), findsOneWidget);

    // El `PopScope` bloquea el back del usuario, no el `pushReplacement` que
    // la pantalla hace por su cuenta.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('siguiente'), findsOneWidget);
  });
}
