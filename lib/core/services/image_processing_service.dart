import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Rango de bytes objetivo + resolución máxima permitida para un tipo de foto.
class ImageTargetSpec {
  const ImageTargetSpec({
    required this.minBytes,
    required this.maxBytes,
    required this.maxWidth,
    required this.maxHeight,
  });

  final int minBytes;
  final int maxBytes;
  final int maxWidth;
  final int maxHeight;
}

/// Comprime y redimensiona fotos de perfil/vehículo a un rango de peso y una
/// resolución máxima concretos, evitando que cada pantalla reinvente su
/// propia lógica de compresión con límites distintos (o sin límite alguno).
class ImageProcessingService {
  const ImageProcessingService();

  static const ImageTargetSpec profile = ImageTargetSpec(
    minBytes: 300 * 1024,
    maxBytes: 800 * 1024,
    maxWidth: 1080,
    maxHeight: 1080,
  );

  // Los dos "escalones" de resolución permitidos para foto de perfil: se
  // intenta primero a la resolución alta y solo se baja si no entra en el
  // peso máximo con calidad aceptable.
  static const int _profileHighRes = 1080;
  static const int _profileLowRes = 720;

  static const ImageTargetSpec vehicle4x3 = ImageTargetSpec(
    minBytes: 500 * 1024,
    maxBytes: 2 * 1024 * 1024,
    maxWidth: 1280,
    maxHeight: 960,
  );

  static const ImageTargetSpec vehicle16x9 = ImageTargetSpec(
    minBytes: 500 * 1024,
    maxBytes: 2 * 1024 * 1024,
    maxWidth: 1920,
    maxHeight: 1080,
  );

  Future<_Dimensions> _readDimensions(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return _Dimensions(frame.image.width, frame.image.height);
  }

  /// Comprime la foto de perfil (ya recortada 1:1) buscando quedar entre
  /// 300KB y 800KB, probando primero 1080×1080 y bajando a 720×720 si no
  /// entra en el peso máximo sin verse mal.
  Future<File> compressProfilePhoto(File file) async {
    final highRes = await _tryCompressToBox(
      file,
      maxSide: _profileHighRes,
      spec: profile,
    );
    if (highRes != null) return highRes;

    final lowRes = await _tryCompressToBox(
      file,
      maxSide: _profileLowRes,
      spec: profile,
    );
    return lowRes ?? file;
  }

  /// Comprime la foto del vehículo buscando quedar entre 500KB y 2MB, en
  /// 1280×960 (4:3) o 1920×1080 (16:9) según la proporción real de la foto.
  Future<File> compressVehiclePhoto(File file) async {
    final dims = await _readDimensions(file);
    final aspect = dims.width / dims.height;
    const aspect4x3 = 4 / 3;
    const aspect16x9 = 16 / 9;
    final spec = (aspect - aspect4x3).abs() <= (aspect - aspect16x9).abs()
        ? vehicle4x3
        : vehicle16x9;

    final result = await _tryCompressToBox(
      file,
      maxSide: spec.maxWidth > spec.maxHeight ? spec.maxWidth : spec.maxHeight,
      spec: spec,
    );
    return result ?? file;
  }

  /// Redimensiona `file` para que quepa en un cuadro de `maxSide` (sin
  /// agrandar imágenes más pequeñas) y prueba calidades descendentes hasta
  /// encontrar una que caiga dentro de `[spec.minBytes, spec.maxBytes]`. Si
  /// ninguna cae exactamente en el rango, devuelve la más grande que no
  /// supere `spec.maxBytes` (nunca se excede el máximo).
  Future<File?> _tryCompressToBox(
    File file, {
    required int maxSide,
    required ImageTargetSpec spec,
  }) async {
    try {
      final dims = await _readDimensions(file);
      final scale = maxSide / (dims.width > dims.height ? dims.width : dims.height);
      final clampedScale = scale < 1.0 ? scale : 1.0; // nunca agrandar
      final targetW = (dims.width * clampedScale).round();
      final targetH = (dims.height * clampedScale).round();

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${maxSide}_comp.webp';

      const qualities = [90, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40, 35, 30];
      File? bestUnderMax;
      for (final q in qualities) {
        final result = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          outPath,
          quality: q,
          minWidth: targetW,
          minHeight: targetH,
          format: CompressFormat.webp,
        );
        if (result == null) continue;
        final wrapped = File(result.path);
        final len = await wrapped.length();
        if (len > spec.maxBytes) continue;
        bestUnderMax = wrapped;
        if (len >= spec.minBytes) return wrapped;
      }
      return bestUnderMax;
    } catch (_) {
      return null;
    }
  }
}

class _Dimensions {
  const _Dimensions(this.width, this.height);
  final int width;
  final int height;
}
