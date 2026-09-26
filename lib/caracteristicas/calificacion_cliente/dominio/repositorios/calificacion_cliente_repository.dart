import '../entidades/calificacion_cliente.dart';

abstract class CalificacionClienteRepository {
  /// Promedio del cliente, o `null` si todavía nadie lo calificó.
  Future<CalificacionCliente?> obtener(String clienteId);
}
