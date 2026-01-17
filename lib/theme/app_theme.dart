import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/app_tamano.dart';


class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColores.background,

    // Colores principales
    colorScheme: ColorScheme.light(
      primary: AppColores.primary,
      secondary: AppColores.secondary,
      error: AppColores.error,
      surface: AppColores.surface,
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColores.surface,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: AppColores.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: AppTamano.title,
        fontWeight: FontWeight.bold,
        color: AppColores.textPrimary,
      ),
    ),

    // Textos
    textTheme: TextTheme(
      titleLarge: TextStyle(
        fontSize: AppTamano.title,
        fontWeight: FontWeight.bold,
        color: AppColores.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: AppTamano.subtitle,
        fontWeight: FontWeight.w600,
        color: AppColores.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: AppTamano.body,
        color: AppColores.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: AppTamano.subtitle,
        color: AppColores.textWhite,
      ),
    ),

    // Botones elevados
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

    // Inputs
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColores.surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppTamano.paddingMD,
        vertical: AppTamano.paddingSM,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTamano.radiusMD),
        borderSide: BorderSide(color: AppColores.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTamano.radiusMD),
        borderSide: BorderSide(color: AppColores.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTamano.radiusMD),
        borderSide: BorderSide(color: AppColores.primary),
      ),
    ),
  );
}
