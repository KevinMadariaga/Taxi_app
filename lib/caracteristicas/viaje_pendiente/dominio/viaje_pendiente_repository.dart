import 'viaje_pendiente.dart';

abstract class ViajePendienteRepository {
  /// Viajes pendientes de [clienteId], lo más próximo primero.
  Stream<List<ViajePendiente>> watch(String clienteId);

  Future<void> cancelar(String id);
}
