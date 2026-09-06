import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/app_tamano.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

class AppThemeConfig {
  static ThemeData get lightTheme => _build(AppPalette.light, Brightness.light);

  static ThemeData get darkTheme => _build(AppPalette.dark, Brightness.dark);

  /// Único builder para ambos temas: recibe la paleta (`AppPalette.light` o
  /// `.dark`) y arma un `ThemeData` equivalente en estructura, así que no hay
  /// que mantener dos copias del mismo `ThemeData` sincronizadas a mano. Los
  /// colores de marca (`AppColores.primary`, `error`, etc.) son iguales en
  /// los dos modos y se leen directo de `AppColores`.
  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: AppColores.primary,
            secondary: AppColores.secondary,
            error: AppColores.error,
            surface: p.surface,
            onSurface: p.textPrimary,
            onPrimary: AppColores.textWhite,
            outline: p.divider,
            surfaceContainerHighest: p.cardBackground,
          )
        : ColorScheme.light(
            primary: AppColores.primary,
            secondary: AppColores.secondary,
            error: AppColores.error,
            surface: p.surface,
            onSurface: p.textPrimary,
            onPrimary: AppColores.textWhite,
            outline: p.divider,
            surfaceContainerHighest: p.cardBackground,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.background,
      extensions: [p],

      colorScheme: colorScheme,

      // Todos los AppBar de la app usan el color de marca fijo (amarillo)
      // con texto/íconos blancos: mismo aspecto en claro y oscuro, así que
      // nunca hay que resolver contraste contra una superficie que cambia
      // de color entre temas.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColores.textWhite),
        titleTextStyle: TextStyle(
          fontSize: AppTamano.title,
          fontWeight: FontWeight.bold,
          color: AppColores.textWhite,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AppColores.primary,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),

      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontSize: AppTamano.title,
          fontWeight: FontWeight.bold,
          color: p.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: AppTamano.subtitle,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        bodyMedium: TextStyle(fontSize: AppTamano.body, color: p.textSecondary),
        labelLarge: TextStyle(
          fontSize: AppTamano.subtitle,
          color: AppColores.textWhite,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(double.infinity, AppTamano.buttonHeight),
          backgroundColor: AppColores.buttonPrimary,
          foregroundColor: AppColores.textWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTamano.radiusMD),
          ),
          textStyle: TextStyle(
            fontSize: AppTamano.subtitle,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppTamano.paddingMD,
          vertical: AppTamano.paddingSM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTamano.radiusMD),
          borderSide: BorderSide(color: p.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTamano.radiusMD),
          borderSide: BorderSide(color: p.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTamano.radiusMD),
          borderSide: BorderSide(color: AppColores.primary),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: AppTamano.subtitle,
          fontWeight: FontWeight.w800,
          color: p.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: AppTamano.body,
          color: p.textSecondary,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.sheetBackground,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: p.cardBackground,
        surfaceTintColor: Colors.transparent,
      ),

      dividerTheme: DividerThemeData(color: p.divider, thickness: 1),

      listTileTheme: ListTileThemeData(
        textColor: p.textPrimary,
        iconColor: p.textSecondary,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColores.primary
              : p.grey400,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColores.primary.withValues(alpha: 0.5)
              : p.grey200,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink900,
        contentTextStyle: TextStyle(color: p.ink50),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
