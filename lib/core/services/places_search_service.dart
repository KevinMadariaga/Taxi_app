import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Sugerencia de Google Places Autocomplete antes de resolver coordenadas.
class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

class PlaceDetails {
  final LatLng location;
  final String formattedAddress;
  final String name;

  const PlaceDetails({
    required this.location,
    required this.formattedAddress,
    required this.name,
  });
}

/// Búsqueda de direcciones vía Google Places, restringida al radio de Ocaña.
///
/// La key de Google vive solo en Secret Manager del lado del servidor (ver
/// functions/index.js → searchPlacesOcana/getPlaceDetails); el cliente nunca
/// la conoce, igual que con Directions.
class PlacesSearchService {
  const PlacesSearchService();

  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<PlacePrediction>> buscar(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final callable = _functions.httpsCallable('searchPlacesOcana');
      final result = await callable
          .call(<String, dynamic>{'query': query.trim()})
          .timeout(const Duration(seconds: 6));

      final predictions = (result.data as Map?)?['predictions'] as List?;
      if (predictions == null) return [];

      return predictions
          .whereType<Map>()
          .map(
            (p) => PlacePrediction(
              placeId: (p['placeId'] ?? '').toString(),
              mainText: (p['mainText'] ?? '').toString(),
              secondaryText: (p['secondaryText'] ?? '').toString(),
            ),
          )
          .where((p) => p.placeId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<PlaceDetails?> obtenerDetalles(String placeId) async {
    try {
      final callable = _functions.httpsCallable('getPlaceDetails');
      final result = await callable
          .call(<String, dynamic>{'placeId': placeId})
          .timeout(const Duration(seconds: 6));

      final data = result.data as Map?;
      final lat = (data?['lat'] as num?)?.toDouble();
      final lng = (data?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return PlaceDetails(
        location: LatLng(lat, lng),
        formattedAddress: (data?['formattedAddress'] ?? '').toString(),
        name: (data?['name'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
