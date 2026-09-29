import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/direccion_format.dart';
import '../../dominio/repositorios/geocodificacion_repository.dart';

/// Geocodificación inversa vía `package:geocoding` (resuelve nativo en
/// Android/iOS). Recorre todos los resultados (el primero a veces es solo un
/// Plus Code) y, si ninguno trae dirección legible, devuelve
/// [textoSinDireccion]: la UI nunca queda en blanco ni muestra coordenadas.
class GeocodificacionRepositoryImpl implements GeocodificacionRepository {
  @override
  Future<String> direccionDesde(LatLng coordenada) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coordenada.latitude,
        coordenada.longitude,
      );
      for (final p in placemarks) {
        final direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.isNotEmpty && !esPlusCode(s)).join(', ');
        if (direccion.isNotEmpty) return direccion;
      }
    } catch (_) {
      // Falla de geocodificación esperable (sin red, punto sin dirección
      // catastral), no un bug: se muestra el texto genérico.
    }
    return textoSinDireccion;
  }
}
