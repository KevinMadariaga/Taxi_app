import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Valida que una foto de perfil contenga un rostro humano real y
/// razonablemente enmarcado, para evitar que clientes/conductores suban
/// cualquier imagen (paisajes, capturas, fotos de terceros a distancia) en
/// vez de una foto propia — protección básica de identidad visible para el
/// otro lado del viaje.
///
/// Corre 100% on-device (ML Kit), sin llamadas a red ni costo de backend.
class FaceDetectionService {
  FaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.2, // el rostro debe ocupar al menos ~20% del cuadro
        ),
      );

  final FaceDetector _detector;

  /// true si `imagePath` contiene al menos un rostro razonablemente grande.
  /// En caso de error de procesamiento (formato raro, fallo del modelo),
  /// devuelve `true` para no bloquear al usuario por un falso negativo del
  /// detector — la validación es una protección adicional, no la única capa.
  Future<bool> hasFace(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return false;
      final input = InputImage.fromFilePath(imagePath);
      final faces = await _detector.processImage(input);
      return faces.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> dispose() async {
    try {
      await _detector.close();
    } catch (_) {}
  }
}
