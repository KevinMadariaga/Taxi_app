import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Tokens de color que sí cambian entre modo claro y oscuro (superficies,
/// texto, separadores, overlays). Los colores de marca (`AppColores.primary`,
/// `error`, `success`, `route`, etc.) NO viven acá: son iguales en ambos
/// temas y se siguen leyendo directo de `AppColores`.
///
/// `AppColores` no se toca — sigue siendo la paleta clara/legacy que leen los
/// ~200 archivos todavía no migrados a `context.palette`, así que no cambian
/// de aspecto mientras se migran uno por uno.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.sheetBackground,
    required this.cardBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.borderSubtle,
    required this.overlayDark,
    required this.overlayLight,
    required this.grey100,
    required this.grey200,
    required this.grey300,
    required this.grey400,
    required this.grey600,
    required this.ink50,
    required this.ink200,
    required this.ink500,
    required this.ink700,
    required this.ink900,
  });

  final Color background;
  final Color surface;
  final Color sheetBackground;
  final Color cardBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color borderSubtle;
  final Color overlayDark;
  final Color overlayLight;
  final Color grey100;
  final Color grey200;
  final Color grey300;
  final Color grey400;
  final Color grey600;
  final Color ink50;
  final Color ink200;
  final Color ink500;
  final Color ink700;
  final Color ink900;

  /// Idéntica a los valores actuales de `AppColores` — el modo claro no
  /// cambia de aspecto con la migración a `ThemeExtension`.
  static const AppPalette light = AppPalette(
    background: AppColores.background,
    surface: AppColores.surface,
    sheetBackground: AppColores.sheetBackground,
    cardBackground: AppColores.cardBackground,
    textPrimary: AppColores.textPrimary,
    textSecondary: AppColores.textSecondary,
    divider: AppColores.divider,
    borderSubtle: AppColores.borderSubtle,
    overlayDark: AppColores.overlayDark,
    overlayLight: AppColores.overlayLight,
    grey100: AppColores.grey100,
    grey200: AppColores.grey200,
    grey300: AppColores.grey300,
    grey400: AppColores.grey400,
    grey600: AppColores.grey600,
    ink50: AppColores.ink50,
    ink200: AppColores.ink200,
    ink500: AppColores.ink500,
    ink700: AppColores.ink700,
    ink900: AppColores.ink900,
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF121417),
    surface: Color(0xFF1B1F24),
    sheetBackground: Color(0xFF1B1F24),
    cardBackground: Color(0xFF20252B),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFA8AEB6),
    divider: Color(0x1FFFFFFF), // blanco 12%, equivalente oscuro de `divider`
    borderSubtle: Color(0x1FFFFFFF),
    overlayDark: Color(0xB3000000), // scrim más marcado sobre fondo oscuro
    overlayLight: Color(0x66000000),
    grey100: Color(0xFF2A2F36),
    grey200: Color(0xFF333941),
    grey300: Color(0xFF3D444D),
    grey400: Color(0xFF565F6A),
    grey600: Color(0xFF8B93A0),
    ink50: Color(0xFF1B1F24),
    ink200: Color(0xFF2E343B),
    ink500: Color(0xFF9098A3),
    ink700: Color(0xFFD3D7DC),
    ink900: Color(0xFFF5F6F8),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? sheetBackground,
    Color? cardBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? borderSubtle,
    Color? overlayDark,
    Color? overlayLight,
    Color? grey100,
    Color? grey200,
    Color? grey300,
    Color? grey400,
    Color? grey600,
    Color? ink50,
    Color? ink200,
    Color? ink500,
    Color? ink700,
    Color? ink900,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      sheetBackground: sheetBackground ?? this.sheetBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      overlayDark: overlayDark ?? this.overlayDark,
      overlayLight: overlayLight ?? this.overlayLight,
      grey100: grey100 ?? this.grey100,
      grey200: grey200 ?? this.grey200,
      grey300: grey300 ?? this.grey300,
      grey400: grey400 ?? this.grey400,
      grey600: grey600 ?? this.grey600,
      ink50: ink50 ?? this.ink50,
      ink200: ink200 ?? this.ink200,
      ink500: ink500 ?? this.ink500,
      ink700: ink700 ?? this.ink700,
      ink900: ink900 ?? this.ink900,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sheetBackground: Color.lerp(sheetBackground, other.sheetBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      overlayDark: Color.lerp(overlayDark, other.overlayDark, t)!,
      overlayLight: Color.lerp(overlayLight, other.overlayLight, t)!,
      grey100: Color.lerp(grey100, other.grey100, t)!,
      grey200: Color.lerp(grey200, other.grey200, t)!,
      grey300: Color.lerp(grey300, other.grey300, t)!,
      grey400: Color.lerp(grey400, other.grey400, t)!,
      grey600: Color.lerp(grey600, other.grey600, t)!,
      ink50: Color.lerp(ink50, other.ink50, t)!,
      ink200: Color.lerp(ink200, other.ink200, t)!,
      ink500: Color.lerp(ink500, other.ink500, t)!,
      ink700: Color.lerp(ink700, other.ink700, t)!,
      ink900: Color.lerp(ink900, other.ink900, t)!,
    );
  }
}

/// Acceso corto a la paleta activa: `context.palette.surface` en vez de
/// `Theme.of(context).extension<AppPalette>()!.surface`. Cae a [AppPalette.light]
/// si por lo que sea el `ThemeData` activo no la registró (no debería pasar:
/// `AppThemeConfig.lightTheme`/`darkTheme` siempre la incluyen).
extension PaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
