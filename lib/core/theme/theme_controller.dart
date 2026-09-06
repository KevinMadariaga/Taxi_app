import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de apariencia (claro/oscuro/sistema) del dispositivo — no de
/// Firestore: es un ajuste del aparato, no del perfil del usuario, así que
/// sobrevive al logout (`AuthService.clearPersistedSessionAndCaches` no
/// conoce esta clave y no debe agregársela) y no viaja entre dispositivos.
///
/// Mismo patrón directo de `SharedPreferences.getInstance()` que ya usan
/// `NotificacionesView`/`NotificacionesConductorView` para sus toggles.
class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Carga la preferencia guardada. Se llama una vez en `main()` ANTES de
  /// `runApp` para que la primera pintura ya use el tema correcto — sin esto
  /// la app arrancaría siempre en claro y "saltaría" a oscuro un frame
  /// después, con el flash blanco que se quiere evitar.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    _themeMode = _decode(stored);
    // No notifyListeners(): todavía no hay listeners antes de runApp.
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
