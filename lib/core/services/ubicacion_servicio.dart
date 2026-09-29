import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';

/// Ubicación puntual del cliente (una lectura, no un stream).
///
/// El tracking continuo vive en `TrackingService` (conductor, 15 m). Aquí se
/// quitaron `startListening`/`escucharUbicacion`/`listenWithCallback`: nadie
/// los usaba y traían `distanceFilter: 1` (un evento por metro, rebuilds y
/// batería). Si el cliente llega a necesitar un stream, usar 5–10 m.
class UbicacionService {
  UbicacionService._internal();
  static final UbicacionService _instance = UbicacionService._internal();
  factory UbicacionService() => _instance;

  /// Solicita permisos y devuelve la ubicación actual una sola vez.
  Future<LatLng?> obtenerUbicacionActual() async {
    final hasPermission = await PermissionsHelper.requestLocationPermission();
    if (!hasPermission) return null;

    try {
      final Position posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LatLng(posicion.latitude, posicion.longitude);
    } catch (_) {
      return null;
    }
  }
}
