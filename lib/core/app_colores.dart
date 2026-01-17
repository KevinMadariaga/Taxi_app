import 'package:flutter/material.dart';


/// Colores de la aplicación (paleta principal para la app de taxi)
class AppColores {
  // Marca / primarios
  static const Color primary = Colores.amarillo; // color principal (CTA)
  static const Color secondary = Colores.azul; // color secundario/acento

  // Superficies y fondos
  static const Color background = Color(0xFFF7F7F8);
  static const Color surface = Colores.blanco;

  // Texto
  static const Color textPrimary = Colores.negro;
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textWhite = Colores.blanco;

  // Botones
  static const Color buttonPrimary = Colores.amarillo;
  static const Color buttonCancel = Colores.rojo;
  static const Color buttonChat = Colores.azul;

  // Separadores / divisores
  static const Color divider = Color(0xFFE6E6E6);

  // Errores
  static const Color error = Colores.rojo;
  static const Color route = Color.fromARGB(255, 250, 204, 0);
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
