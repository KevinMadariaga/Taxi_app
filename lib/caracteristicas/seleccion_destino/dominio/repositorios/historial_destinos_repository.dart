import '../entidades/ubicacion_entity.dart';

/// Contrato del historial de destinos recientemente seleccionados por el
/// cliente en esta pantalla. A diferencia de los favoritos (guardado
/// explícito del usuario), acá se registra automáticamente cada destino
/// confirmado — sin acción explícita del usuario.
abstract class HistorialDestinosRepository {
  /// Del más reciente al más antiguo.
  Future<List<UbicacionEntity>> obtener();

  /// Registra [destino] como el más reciente. Si ya estaba en el historial
  /// (misma posición), lo mueve al frente en vez de duplicarlo.
  Future<void> registrar(UbicacionEntity destino);
}
