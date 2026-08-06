import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../entidades/ubicacion_entity.dart';

/// Contrato de acceso a las ubicaciones del usuario (favoritos guardados en
/// `usuarios/{uid}/favoritos` y el espejo plano en `ubicaciones` usado para
/// autocompletar destino). Ninguna clase debe depender de la implementación
/// concreta, solo de esta interfaz.
abstract class UbicacionesRepository {
  Future<void> guardarFavorito({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  });

  Future<List<UbicacionEntity>> favoritosPorTipo(String tipo, {int? limit});

  /// Ubicaciones guardadas por el usuario actual (colección `ubicaciones`),
  /// sin filtrar todavía por texto de búsqueda — eso lo hace el caso de uso
  /// que combina fuentes. Devuelve vacío si no hay sesión.
  ///
  /// El filtrado por dueño es parte de la QUERY, no un post-filtro en Dart:
  /// las reglas de `ubicaciones` solo permiten leer los documentos propios.
  Future<List<UbicacionEntity>> todasLasGuardadas();
}
