import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/services/tracking_service.dart';

/// Sustituye `obtenerUbicacionActual` (única llamada externa relevante de
/// TrackingService para InicioConductorViewmodel) por una posición fija.
class FakeTrackingService extends TrackingService {
  FakeTrackingService([this.position]);

  Position? position;

  @override
  Future<Position?> obtenerUbicacionActual() async => position;
}

Position fakePosition(double lat, double lng) {
  return Position(
    longitude: lng,
    latitude: lat,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
