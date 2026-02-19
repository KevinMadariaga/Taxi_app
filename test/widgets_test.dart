import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';

void main() {
  group('Widgets', () {
    testWidgets('MapLoadingWidget se puede construir', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MapLoadingWidget()));
      expect(find.byType(MapLoadingWidget), findsOneWidget);
    });
  });
}
