import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/services/places_search_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/ubicacion_resultado.dart';

/// Lógica de negocio (sin `BuildContext`) extraída de
/// `DestinoSeleccionView` / `_DestinoSeleccionViewState`: normalización de
/// texto/coordenadas, decisiones de filtrado y combinación de resultados de
/// búsqueda, y parsing de coordenadas desde texto compartido.
///
/// Clase plana (sin `ChangeNotifier`): no maneja estado ni reconstruye UI,
/// la vista sigue instanciándola como campo y llamando `setState` como antes.
class DestinoSeleccionViewModel {
  const DestinoSeleccionViewModel();

  // Centro y radio de Ocaña (Norte de Santander) usados para filtrar
  // resultados: mismo círculo que restringe la búsqueda en el servidor (ver
  // functions/index.js → OCANA_CENTER/OCANA_RADIUS_METERS), aplicado acá
  // también a los favoritos guardados en Firestore para que nunca se cuele
  // una ubicación de otra ciudad y confunda al usuario.
  static const LatLng ocanaCenter = LatLng(8.2488503, -73.3471543);
  static const double ocanaRadioMetros = 9000;

  String keyFromLatLng(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  }

  String coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  String buildDireccionAmigable(Placemark p, LatLng fallback) {
    final direccion = [
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
    ].where((s) => (s ?? '').trim().isNotEmpty).join(', ');
    if (direccion.trim().isEmpty) return coordsText(fallback);
    return direccion;
  }

  bool estaDentroDeOcana(LatLng punto) {
    final distancia = Geolocator.distanceBetween(
      ocanaCenter.latitude,
      ocanaCenter.longitude,
      punto.latitude,
      punto.longitude,
    );
    return distancia <= ocanaRadioMetros;
  }

  /// Combina resultados de dos fuentes para darle al usuario varias formas
  /// de encontrar su destino:
  /// - Sus propias ubicaciones guardadas (`ubicaciones` en Firestore).
  /// - Direcciones reales vía Google Places, acotadas al radio de Ocaña.
  /// Las guardadas se filtran al radio de Ocaña para no confundir con otra
  /// ciudad.
  List<UbicacionResultado> combinarSugerencias({
    required List<UbicacionResultado> guardadas,
    required List<PlacePrediction> dePlaces,
  }) {
    final guardadasFiltradas = guardadas
        .where((r) => r.location == null || estaDentroDeOcana(r.location!))
        .toList();

    final desdePlaces = dePlaces
        .map(
          (p) => UbicacionResultado(
            location: null,
            nombre: p.mainText,
            direccion: p.secondaryText.isNotEmpty
                ? p.secondaryText
                : p.mainText,
            placeId: p.placeId,
          ),
        )
        .toList();

    return [...guardadasFiltradas, ...desdePlaces];
  }

  /// Filtra las ubicaciones guardadas del usuario que coincidan con [query]
  /// (por nombre o dirección) y las mapea a [UbicacionResultado]. Descarta
  /// documentos que pertenezcan a otro usuario ([currentUid]).
  List<UbicacionResultado> filtrarYMapearUbicacionesGuardadas({
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String query,
    required String currentUid,
  }) {
    final normalizado = query.toLowerCase();
    return docs
        .where((doc) {
          final data = doc.data();
          final nombre = (data['nombre'] ?? '') as String;
          final direccion = (data['direccion'] ?? '') as String;
          final ownerId = data['userId'] as String?;

          if (ownerId != null && ownerId.isNotEmpty && ownerId != currentUid) {
            return false;
          }

          final textoBusqueda = '$nombre $direccion'.toLowerCase();
          return textoBusqueda.contains(normalizado);
        })
        .map((doc) {
          final data = doc.data();
          final geopoint = data['ubicacion'] as GeoPoint;
          final nombre = (data['nombre'] ?? '') as String;
          final direccion = (data['direccion'] ?? '') as String;
          return UbicacionResultado(
            location: LatLng(geopoint.latitude, geopoint.longitude),
            nombre: nombre,
            direccion: direccion.isNotEmpty ? direccion : nombre,
          );
        })
        .toList();
  }

  Future<LatLng?> extraerLatLngDesdeTexto(String text) async {
    final reg = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
    final matches = reg.allMatches(text).toList();
    if (matches.isNotEmpty) {
      final selected = matches.length >= 2 ? matches[1] : matches[0];
      final lat = double.tryParse(selected.group(1) ?? '');
      final lng = double.tryParse(selected.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final urlMatch = RegExp(r'(https?://[^\s]+)').firstMatch(text);
    final rawUrl = (urlMatch?.group(1) ?? text).trim();
    if (rawUrl.isNotEmpty && rawUrl.contains('google.com/maps')) {
      final atReg = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)(?:,|z)');
      final atMatches = atReg.allMatches(rawUrl).toList();
      if (atMatches.isNotEmpty) {
        if (rawUrl.contains('/place/')) {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        } else if (rawUrl.contains('/dir/')) {
          final m = atMatches.length > 1 ? atMatches[1] : atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        } else {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    try {
      final urlMatch2 = RegExp(r'(https?://[^\s]+)').firstMatch(text);
      final rawUrl2 = (urlMatch2?.group(1) ?? text).trim();
      if (rawUrl2.isEmpty) return null;

      Uri uri;
      try {
        uri = Uri.parse(rawUrl2);
      } catch (_) {
        return null;
      }
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$rawUrl2');
      }

      final client = http.Client();
      try {
        bool isShortGoogleMaps = uri.host.contains('maps.app.goo.gl');
        String target = '';
        if (isShortGoogleMaps) {
          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..maxRedirects = 1
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';

          final resp = await client
              .send(req)
              .timeout(const Duration(seconds: 6));
          target = resp.headers['location'] ?? '';
          if (target.isEmpty) {
            target = await resp.stream.bytesToString();
          }
        } else {
          target = uri.toString();
        }
        if (target.isEmpty) return null;

        final targetMatches = reg.allMatches(target).toList();
        if (targetMatches.isNotEmpty) {
          final selected = targetMatches.length >= 2
              ? targetMatches[1]
              : targetMatches[0];
          final lat = double.tryParse(selected.group(1) ?? '');
          final lng = double.tryParse(selected.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }

        if (isShortGoogleMaps && target.isNotEmpty) {
          try {
            final resp2 = await client
                .get(Uri.parse(target))
                .timeout(const Duration(seconds: 6));
            final html = resp2.body;
            final htmlMatches = reg.allMatches(html).toList();
            if (htmlMatches.isNotEmpty) {
              final selected = htmlMatches.length >= 2
                  ? htmlMatches[1]
                  : htmlMatches[0];
              final lat = double.tryParse(selected.group(1) ?? '');
              final lng = double.tryParse(selected.group(2) ?? '');
              if (lat != null && lng != null) {
                return LatLng(lat, lng);
              }
            }
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'SeleccionDestino');
          }
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}
