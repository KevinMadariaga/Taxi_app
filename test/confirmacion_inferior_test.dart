import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

void main() {
  testWidgets('aviso de éxito sobrevive al pop y se va a los 2 s', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.dark]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        mostrarAvisoExito(
                          ctx,
                          titulo: 'Perfil actualizado',
                          mensaje: 'Tus cambios quedaron guardados.',
                        );
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('guardar'),
                    ),
                  ),
                ),
              ),
              child: const Text('editar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('guardar'));
    await tester.pumpAndSettle();

    // De vuelta en la pantalla anterior, con el aviso visible y sin modal.
    expect(find.text('editar'), findsOneWidget);
    expect(find.text('Perfil actualizado'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Perfil actualizado'), findsNothing);
  });
}
