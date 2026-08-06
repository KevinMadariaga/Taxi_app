import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/error_reporter.dart';

import '../entidades/ubicacion_entity.dart';
import '../repositorios/lugares_repository.dart';
import '../repositorios/ubicaciones_repository.dart';

/// Combina las ubicaciones guardadas por el propio usuario (colección
/// `ubicaciones`, filtradas por texto) con direcciones reales de Google
/// Places, para darle al usuario varias formas de encontrar su destino.
///
/// Las guardadas se acotan al radio de Ocaña (mismo círculo que ya usa el
/// servidor para Places, ver `functions/index.js` → `OCANA_CENTER`/
/// `OCANA_RADIUS_METERS`) para no confundir con ubicaciones de otra ciudad
/// que hayan quedado guardadas por error.
class BuscarDestinosUseCase {
  BuscarDestinosUseCase(this._ubicaciones, this._lugares);

  final UbicacionesRepository _ubicaciones;
  final LugaresRepository _lugares;

  static const LatLng ocanaCenter = LatLng(8.2488503, -73.3471543);
  static const double ocanaRadioMetros = 9000;

  bool _estaDentroDeOcana(LatLng punto) {
    final distancia = Geolocator.distanceBetween(
      ocanaCenter.latitude,
      ocanaCenter.longitude,
      punto.latitude,
      punto.longitude,
    );
    return distancia <= ocanaRadioMetros;
  }

  Future<List<UbicacionEntity>> call(String query) async {
    final normalizado = query.trim();
    if (normalizado.isEmpty) return [];

    // Las dos fuentes se resuelven de forma INDEPENDIENTE: con un
    // `Future.wait` pelado, un fallo en las guardadas (p. ej.
    // `permission-denied`) hacía fallar el conjunto y descartaba también los
    // resultados de Places que sí habían llegado — el usuario escribía un
    // destino y no veía ni una sugerencia. Cada rama degrada a lista vacía.
    final resultados = await Future.wait([
      _sinFallar(() => _buscarGuardadas(normalizado)),
      _sinFallar(() => _lugares.buscar(normalizado)),
    ]);

    return [...resultados[0], ...resultados[1]];
  }

  /// Degrada a lista vacía, pero SÍ reporta: al aislar el fallo acá, el
  /// ViewModel ya no lo ve, así que sin este report un `permission-denied` o
  /// un índice faltante quedaría completamente invisible.
  Future<List<UbicacionEntity>> _sinFallar(
    Future<List<UbicacionEntity>> Function() fuente,
  ) async {
    try {
      return await fuente();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscar_destinos_usecase');
      return const [];
    }
  }

  Future<List<UbicacionEntity>> _buscarGuardadas(String query) async {
    final normalizado = query.toLowerCase();
    final guardadas = await _ubicaciones.todasLasGuardadas();
    return guardadas.where((u) {
      if (u.position != null && !_estaDentroDeOcana(u.position!)) return false;
      final texto = '${u.nombre} ${u.direccion}'.toLowerCase();
      return texto.contains(normalizado);
    }).toList();
  }
}
