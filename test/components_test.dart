import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/components/boton.dart';



void main() {
  group('Components', () {
    testWidgets('CustomButton se puede construir', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CustomButton(
          text: 'Test',
          onPressed: () {},
        ),
      ));
      expect(find.byType(CustomButton), findsOneWidget);
    });
  });
}
