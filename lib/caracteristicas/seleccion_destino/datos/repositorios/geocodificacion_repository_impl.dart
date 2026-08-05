import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../dominio/repositorios/geocodificacion_repository.dart';

/// Geocodificación inversa vía `package:geocoding` (resuelve nativo en
/// Android/iOS). Si no hay resultado o la resolución falla (sin red, sin
/// datos catastrales, etc.), cae a las coordenadas formateadas como texto —
/// la UI siempre tiene algo mostrable, nunca queda en blanco.
class GeocodificacionRepositoryImpl implements GeocodificacionRepository {
  @override
  Future<String> direccionDesde(LatLng coordenada) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coordenada.latitude,
        coordenada.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        if (direccion.isNotEmpty) return direccion;
      }
    } catch (_) {
      // Fallback silencioso a coordenadas: falla de geocodificación es
      // esperable (sin red, punto sin dirección catastral) y no un bug.
    }
    return _formatoCoordenadas(coordenada);
  }

  String _formatoCoordenadas(LatLng coordenada) {
    return '${coordenada.latitude.toStringAsFixed(6)}, '
        '${coordenada.longitude.toStringAsFixed(6)}';
  }
}
