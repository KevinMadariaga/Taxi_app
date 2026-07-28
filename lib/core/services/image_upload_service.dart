import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Encapsula la subida/borrado de archivos en Firebase Storage, para que las
/// Views/ViewModels que suben fotos (perfil, vehículo) no toquen
/// `FirebaseStorage.instance` directo cada una por su lado. La compresión
/// previa sigue siendo responsabilidad de [ImageProcessingService] — este
/// servicio solo mueve bytes ya listos hacia Storage.
class ImageUploadService {
  ImageUploadService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Sube [file] a [storagePath] y devuelve la URL de descarga.
  Future<String> uploadFile({
    required File file,
    required String storagePath,
  }) async {
    final ref = _storage.ref().child(storagePath);
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Borra el archivo referenciado por [url] (best-effort: si falla, reporta
  /// y no relanza — una foto vieja huérfana no debe bloquear el flujo
  /// principal de guardar/activar).
  Future<void> deleteByUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'image_upload_service');
    }
  }
}
