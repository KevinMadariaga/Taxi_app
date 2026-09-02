import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../entidades/ubicacion_entity.dart';

/// Contrato de acceso a las ubicaciones favoritas del usuario, guardadas en
/// `usuarios/{uid}/favoritos`. Ninguna clase debe depender de la
/// implementación concreta, solo de esta interfaz.
abstract class UbicacionesRepository {
  /// Devuelve el id del documento creado.
  Future<String> guardarFavorito({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  });

  Future<void> eliminarFavorito(String id);

  Future<List<UbicacionEntity>> favoritos({int? limit});

  /// Todos los favoritos del usuario actual, sin filtrar todavía por texto de
  /// búsqueda — eso lo hace el caso de uso que combina fuentes. Alimenta el
  /// autocompletado de destino. Devuelve vacío si no hay sesión.
  Future<List<UbicacionEntity>> todasLasGuardadas();
}
