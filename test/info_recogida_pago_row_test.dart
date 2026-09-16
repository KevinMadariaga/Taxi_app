// Fila "Recoger en" / "Pagará con" de la preview de solicitud — verifica que
// Nequi use su logo (`assets/img/nequi.png`), no el ícono genérico de
// tarjeta, y que los demás métodos sigan cayendo al `Icon` de siempre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/widgets/preview_solicitud/widgets/info_recogida_pago_row.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? metodoPago) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoRecogidaPagoRow(
            direccionRecogida: 'Calle 1 # 2-3',
            metodoPago: metodoPago,
          ),
        ),
      ),
    );
  }

  testWidgets('Nequi muestra el logo de marca, no un ícono genérico', (
    tester,
  ) async {
    await pump(tester, 'Nequi');

    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.credit_card), findsNothing);
  });

  testWidgets('Efectivo sigue usando el ícono de dinero', (tester) async {
    await pump(tester, 'Efectivo');

    expect(find.byIcon(Icons.attach_money), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
