import '../entidades/estadistica_dia.dart';

abstract class EstadisticasRepository {
  /// Los últimos [dias] días hasta hoy (el más viejo primero), en vivo.
  Stream<List<EstadisticaDia>> watchUltimosDias(int dias);
}
