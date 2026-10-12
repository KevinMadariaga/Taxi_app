import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Lo que pasó con las solicitudes creadas un día (hora de Colombia).
/// Lo cuentan las Cloud Functions `estadisticas*` en el momento de cada
/// evento: las canceladas se borran a los 30 min y no se podrían contar
/// después.
@immutable
class EstadisticaDia {
  const EstadisticaDia({
    required this.dia,
    this.creadas = 0,
    this.completadas = 0,
    this.canceladas = 0,
    this.sinRespuesta = 0,
    this.clientesUnicos = 0,
    this.porHora = const [],
  });

  /// Medianoche del día (fecha local, sin hora).
  final DateTime dia;
  final int creadas;
  final int completadas;
  final int canceladas;
  final int sinRespuesta;

  /// Usuarios distintos que crearon al menos una solicitud ese día.
  final int clientesUnicos;

  /// Solicitudes creadas por hora (24 posiciones; vacío si no hubo).
  final List<int> porHora;

  /// Creadas que todavía no llegan a un final (buscando, en viaje…).
  int get enCurso =>
      math.max(0, creadas - completadas - canceladas - sinRespuesta);

  /// Fracción de las creadas que se completó (0 si no hubo).
  double get tasaCompletado => creadas == 0 ? 0 : completadas / creadas;

  int horaDe(int h) => h < porHora.length ? porHora[h] : 0;
}

/// Hoy en Colombia (UTC-5 fijo, sin horario de verano), a medianoche.
DateTime hoyColombia([DateTime? ahoraUtc]) {
  final c = (ahoraUtc ?? DateTime.now().toUtc()).subtract(
    const Duration(hours: 5),
  );
  return DateTime(c.year, c.month, c.day);
}

/// Clave del documento: `AAAA-MM-DD`.
String claveDia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Los últimos [n] días hasta [hoy] (el más viejo primero), con ceros en
/// los días sin documento: la gráfica no debe saltarse días sin viajes.
List<EstadisticaDia> completarDias(
  List<EstadisticaDia> datos, {
  required DateTime hoy,
  required int n,
}) {
  final porClave = {for (final d in datos) claveDia(d.dia): d};
  return [
    for (var i = n - 1; i >= 0; i--)
      () {
        final dia = DateTime(hoy.year, hoy.month, hoy.day - i);
        return porClave[claveDia(dia)] ?? EstadisticaDia(dia: dia);
      }(),
  ];
}
