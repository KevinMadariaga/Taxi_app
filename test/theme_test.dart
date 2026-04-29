import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/app_tamano.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

void main() {
  group('Theme', () {
    test('AppThemeConfig puede instanciarse', () {
      final theme = AppThemeConfig();
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
