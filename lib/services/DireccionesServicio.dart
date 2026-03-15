import 'dart:convert';
import 'package:http/http.dart' as http;

class Direcciones {

  final String apiKey = "AIzaSyBijCV2BttW2Sat4GiASFtNOn3zfIBvD-4";

  Future<String?> getPolyline(
      double originLat,
      double originLng,
      double destLat,
      double destLng
      ) async {

    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$originLat,$originLng"
        "&destination=$destLat,$destLng"
        "&mode=driving"
        "&key=$apiKey";

    try {

      final response = await http.get(Uri.parse(url));

      print("🌍 URL DIRECTIONS:");
      print(url);

      print("📡 RESPUESTA DIRECTIONS:");
      print(response.body);

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data["status"] == "OK") {
        print("🗺️ DIRECTIONS API OK");
        print("Ruta obtenida correctamente");

        final points = data["routes"][0]["overview_polyline"]["points"];
        print("Polyline encoded: $points");
      } else {
        print("⚠️ DIRECTIONS API FALLÓ");
        print("Status: ${data["status"]}");
      }

        if (data["routes"].isNotEmpty) {

          return data["routes"][0]["overview_polyline"]["points"];

        }

      }

      return null;

    } catch (e) {

      print("Error obteniendo ruta: $e");
      return null;

    }

  }

  /// Obtiene el tiempo estimado (en segundos) entre dos ubicaciones usando Google Directions API.
  Future<int?> getEstimatedDuration(
      double originLat,
      double originLng,
      double destLat,
      double destLng
      ) async {
    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$originLat,$originLng"
        "&destination=$destLat,$destLng"
        "&mode=driving"
        "&key=$apiKey";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["status"] == "OK" && data["routes"].isNotEmpty) {
          final legs = data["routes"][0]["legs"];
          if (legs != null && legs.isNotEmpty) {
            final duration = legs[0]["duration"];
            if (duration != null && duration["value"] != null) {
              return duration["value"] as int; // segundos
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}