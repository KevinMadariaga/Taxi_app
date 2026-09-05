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
  ///
  /// Manda `contentType` explícito (inferido de la extensión de
  /// [storagePath], todas las llamadas actuales usan `.webp` o `.jpg`) en vez
  /// de dejar que el SDK lo adivine: `storage.rules` exige
  /// `contentType.matches('image/.*')` en la escritura (auditoría de
  /// seguridad — antes cualquier archivo, de cualquier tamaño, podía subirse
  /// a `usuarios/{uid}/...`), y esa condición solo es fiable si el cliente
  /// manda el header, no si Storage lo infiere.
  Future<String> uploadFile({
    required File file,
    required String storagePath,
  }) async {
    final ref = _storage.ref().child(storagePath);
    final lower = storagePath.toLowerCase();
    final contentType = lower.endsWith('.webp')
        ? 'image/webp'
        : lower.endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    await ref.putFile(file, SettableMetadata(contentType: contentType));
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
