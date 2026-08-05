import '../entidades/ubicacion_entity.dart';

/// Contrato de búsqueda de direcciones reales (Google Places), restringida al
/// radio de cobertura del servicio del lado del servidor.
abstract class LugaresRepository {
  Future<List<UbicacionEntity>> buscar(String query);

  /// Resuelve coordenadas + dirección formateada para una [UbicacionEntity]
  /// que vino de Places sin `position` (solo con `placeId`).
  Future<UbicacionEntity?> detalle(String placeId);
}
