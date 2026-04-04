import 'dart:math';

class Mapa {
  static double calcularBearing(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    double lat1 = startLat * pi / 180;
    double lat2 = endLat * pi / 180;
    double dLon = (endLng - startLng) * pi / 180;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    double brng = atan2(y, x);

    brng = brng * 180 / pi;

    return (brng + 360) % 360;
  }
}
