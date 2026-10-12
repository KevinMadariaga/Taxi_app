import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Comprime una imagen a WebP para subirla a Storage sin que pese de más,
/// con el mismo criterio que la foto de perfil
/// (`ClientProfileImageDataSource`): prueba de mayor a menor calidad y
/// ancho y se queda con la primera que entra en [maxBytes]. Empieza alto
/// (calidad 88 al ancho completo) para no perder nitidez; solo baja si hace
/// falta.
///
/// [proporcion] (ancho / alto) fija el alto de cada intento: el plugin
/// escala para cubrir `minWidth × minHeight` y nunca agranda.
Future<Uint8List> optimizarAWebP(
  Uint8List fuente, {
  required double proporcion,
  required List<int> anchos,
  required int maxBytes,
  List<int> calidades = const [88, 82, 76],
}) async {
  Uint8List? mejor;
  for (final calidad in calidades) {
    for (final ancho in anchos) {
      final r = await FlutterImageCompress.compressWithList(
        fuente,
        format: CompressFormat.webp,
        quality: calidad,
        minWidth: ancho,
        minHeight: (ancho / proporcion).round(),
        keepExif: false,
      );
      if (r.isEmpty) continue;
      final candidata = Uint8List.fromList(r);
      if (mejor == null || candidata.length < mejor.length) mejor = candidata;
      if (candidata.length <= maxBytes) return candidata;
    }
  }
  // Una imagen muy cargada de detalle puede no bajar del tope: se sube la
  // más liviana lograda (siempre muy por debajo del límite de 5 MB de
  // storage.rules) en vez de rechazarla.
  if (mejor != null) return mejor;
  throw StateError('No se pudo optimizar la imagen.');
}
