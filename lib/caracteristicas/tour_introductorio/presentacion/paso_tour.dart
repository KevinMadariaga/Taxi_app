import 'package:flutter/widgets.dart';

/// Un paso del recorrido: qué parte de la pantalla iluminar y qué decir.
class PasoTour {
  const PasoTour({
    required this.objetivo,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    this.margen = 8,
    this.radio = 18,
  });

  /// Clave del widget a iluminar. Si no está montado al llegar a este paso
  /// (p. ej. una sección que hoy no se muestra), el paso se omite.
  final GlobalKey objetivo;
  final String titulo;
  final String descripcion;
  final IconData icono;

  /// Aire alrededor del widget dentro del foco.
  final double margen;
  final double radio;
}
