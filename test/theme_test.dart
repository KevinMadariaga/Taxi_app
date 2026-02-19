import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/app_tamano.dart';
import 'package:taxi_app/theme/app_theme.dart';

void main() {
  group('Theme', () {
    test('AppTheme puede instanciarse', () {
      final theme = AppTheme();
      expect(theme, isNotNull);
    });
    test('AppColores puede instanciarse', () {
      final colores = AppColores();
      expect(colores, isNotNull);
    });
    test('AppTamano puede instanciarse', () {
      final tamano = AppTamano();
      expect(tamano, isNotNull);
    });
  });
}
