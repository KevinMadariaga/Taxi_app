import 'package:flutter/material.dart';

/// Colores de la aplicación (paleta principal para la app de taxi)
class AppColores {
  // Marca / primarios — antes amarillo (`0xFFFACC00`), migrado al naranja
  // "ride" (mismo valor que `brand400`, definido más abajo — el naranja
  // visible del círculo del vehículo y el CTA "Ya llegué al punto" en
  // "Recoge al cliente"; `brand700` es más oscuro/rojizo, solo válido como
  // fondo sólido con texto blanco) para que todos los botones/acentos de
  // la app compartan ESE naranja, no el más oscuro.
  static const Color primary = Color(0xFFFFB020); // color principal (CTA)
  static const Color secondary = Colores.azul; // color secundario/acento
  // Naranja oscurecido: para iconos sobre fondos teñidos con `primary`,
  // donde el naranja base pierde contraste.
  static const Color primaryDark = Color(0xFFC2410C);

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

  // Trazado de ruta en el mapa: el amarillo de marca de la app, no el azul
  // de navegación de Google Maps.
  static const Color route = Colores.amarillo;

  // Estados
  static const Color success = Color(0xFF2E7D32); // verde éxito
  static const Color warning = Color(0xFFFFA000); // ámbar advertencia
  @Deprecated('usar AppColores.brand500 (o brand50/brand900 para badges)')
  static const Color accentOrange = Colores.naranja; // resaltados/badges

  // Escala de marca "ride" — chips, badges, botón sólido de marca y
  // acentos de mapa (marker, relleno de barra de progreso). `brand500` da
  // ~3.5:1 de contraste con blanco: solo superficies grandes/íconos, NUNCA
  // texto blanco encima. El único naranja válido para texto blanco sobre
  // fondo sólido es `brand700`.
  static const Color brand50 = Color(0xFFFFF4E6);
  static const Color brand200 = Color(0xFFFFD9A8);
  static const Color brand400 = Color(0xFFFFB020);
  static const Color brand500 = Color(0xFFF26212);
  static const Color brand700 = Color(0xFFC2410C);
  static const Color brand900 = Color(0xFF7C2A08);

  // Escala neutra "ink" — texto y bordes de la línea de botones
  // secundario/pill (ver `RideButtonStyles`).
  static const Color ink50 = Color(0xFFF5F6F8);
  static const Color ink200 = Color(0xFFE2E5EA);
  static const Color ink500 = Color(0xFF6B7480);
  static const Color ink700 = Color(0xFF2B3138);
  static const Color ink900 = Color(0xFF101418);

  // Estados de sistema (distintos de `success`/`warning`/`error` de
  // arriba, que siguen vigentes para el resto de la app): `danger` es el
  // rojo de SOS/cancelar, `info` solo para elementos informativos de mapa
  // — nunca para botones.
  static const Color danger = Color(0xFFB3261E);
  static const Color info = Color(0xFF1D4ED8);

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

  static const Color amarillo = Color(
    0xFFFFB020,
  ); // CTA — migrado de amarillo a naranja "ride" (mismo valor de brand400)
  static const Color azul = Color(0xFF0A66C2); // accent blue
  static const Color naranja = Color(0xFFFF7A1A); // acento naranja
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color negro = Color(0xFF000000);
  static const Color rojo = Color(0xFFD32F2F);
}
