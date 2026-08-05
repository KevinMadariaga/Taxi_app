import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:taxi_app/core/utils/error_reporter.dart';

/// Parsea coordenadas desde texto pegado por el usuario: un par "lat,lng"
/// directo, un link `google.com/maps/@lat,lng` (place o dir), o un link corto
/// `maps.app.goo.gl` (sigue el redirect — y si hace falta, el HTML de destino
/// — hasta encontrar coordenadas).
class ExtraerUbicacionDesdeTextoUseCase {
  const ExtraerUbicacionDesdeTextoUseCase();

  static final RegExp _latLngReg = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
  static final RegExp _urlReg = RegExp(r'(https?://[^\s]+)');
  static final RegExp _atReg = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)(?:,|z)');

  Future<LatLng?> call(String text) async {
    final directo = _extraerDePar(text, _latLngReg);
    if (directo != null) return directo;

    final rawUrl = (_urlReg.firstMatch(text)?.group(1) ?? text).trim();
    if (rawUrl.isNotEmpty && rawUrl.contains('google.com/maps')) {
      final desdeAt = _extraerDeGoogleMapsUrl(rawUrl);
      if (desdeAt != null) return desdeAt;
    }

    return _seguirLinkCorto(rawUrl);
  }

  LatLng? _extraerDePar(String text, RegExp reg, {bool preferSegundo = true}) {
    final matches = reg.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final selected = (preferSegundo && matches.length >= 2)
        ? matches[1]
        : matches[0];
    final lat = double.tryParse(selected.group(1) ?? '');
    final lng = double.tryParse(selected.group(2) ?? '');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _extraerDeGoogleMapsUrl(String rawUrl) {
    final atMatches = _atReg.allMatches(rawUrl).toList();
    if (atMatches.isEmpty) return null;

    final RegExpMatch m;
    if (rawUrl.contains('/place/')) {
      m = atMatches[0];
    } else if (rawUrl.contains('/dir/')) {
      m = atMatches.length > 1 ? atMatches[1] : atMatches[0];
    } else {
      m = atMatches[0];
    }
    final lat = double.tryParse(m.group(1) ?? '');
    final lng = double.tryParse(m.group(2) ?? '');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<LatLng?> _seguirLinkCorto(String rawUrl) async {
    if (rawUrl.isEmpty) return null;

    Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return null;
    }
    if (!uri.hasScheme) {
      try {
        uri = Uri.parse('https://$rawUrl');
      } catch (_) {
        return null;
      }
    }

    final client = http.Client();
    try {
      final isShortGoogleMaps = uri.host.contains('maps.app.goo.gl');
      String target;
      if (isShortGoogleMaps) {
        final req = http.Request('GET', uri)
          ..followRedirects = false
          ..maxRedirects = 1
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';
        final resp = await client.send(req).timeout(const Duration(seconds: 6));
        target = resp.headers['location'] ?? '';
        if (target.isEmpty) {
          target = await resp.stream.bytesToString();
        }
      } else {
        target = uri.toString();
      }
      if (target.isEmpty) return null;

      final directo = _extraerDePar(target, _latLngReg);
      if (directo != null) return directo;

      if (isShortGoogleMaps) {
        try {
          final resp2 = await client
              .get(Uri.parse(target))
              .timeout(const Duration(seconds: 6));
          final desdeHtml = _extraerDePar(resp2.body, _latLngReg);
          if (desdeHtml != null) return desdeHtml;
        } catch (e, st) {
          ErrorReporter.report(
            e,
            st,
            reason: 'ExtraerUbicacionDesdeTextoUseCase',
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
