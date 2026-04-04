import 'package:flutter/material.dart';

/// Colores de la aplicación (paleta principal para la app de taxi)
class AppColores {
  // Marca / primarios
  static const Color primary = Color(0xFFFACC00); // color principal (CTA)
  static const Color secondary = Colores.azul; // color secundario/acento

  // Superficies y fondos
  static const Color background = Color(0xFFF7F7F8);
  static const Color surface = Colores.blanco;
  static const Color sheetBackground =
      surface; // fondos de sheets, tarjetas grandes
  static const Color cardBackground = surface; // tarjetas y contenedores

  // Texto
  static const Color textPrimary = Colores.negro;
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textWhite = Colores.blanco;
  static const Color textWhiteMuted = Color(
    0xB3FFFFFF,
  ); // blanco con opacidad ~70%

  // Botones
  static const Color buttonPrimary = Colores.amarillo;
  static const Color buttonCancel = Colores.rojo;
  static const Color buttonChat = Colores.azul;

  // Separadores / divisores
  static const Color divider = Color(0xFFE6E6E6);

  // Grises neutros para bordes, placeholders, etc.
  static const Color grey100 = Color(0xFFF5F5F5); // similar a Colors.grey[100]
  static const Color grey200 = Color(0xFFEEEEEE); // similar a Colors.grey[200]
  static const Color grey300 = Color(0xFFE0E0E0); // similar a Colors.grey[300]
  static const Color grey400 = Color(0xFFBDBDBD); // similar a Colors.grey[400]
  static const Color grey600 = Color(0xFF757575); // similar a Colors.grey[600]

  // Errores
  static const Color error = Colores.rojo;
  static const Color route = Color.fromARGB(255, 250, 204, 0);

  // Estados
  static const Color success = Color(0xFF2E7D32); // verde éxito
  static const Color warning = Color(0xFFFFA000); // ámbar advertencia

  // Overlays / scrims
  static const Color overlayDark = Color(
    0x73000000,
  ); // similar a Colors.black45
  static const Color overlayLight = Color(
    0x42000000,
  ); // similar a Colors.black26

  // Bordes y sombras sutiles
  static const Color borderSubtle = Color(
    0x1F000000,
  ); // equivalente a Colors.black12
}

/// Paleta base con nombres usados por `AppColores`
class Colores {
  Colores._();

  static const Color amarillo = Color(0xFFFACC00); // CTA / taxi yellow
  static const Color azul = Color(0xFF0A66C2); // accent blue
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color negro = Color(0xFF000000);
  static const Color rojo = Color(0xFFD32F2F);
}
