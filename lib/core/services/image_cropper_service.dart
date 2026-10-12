import 'dart:io';

import 'package:image_cropper/image_cropper.dart';

class ImageCropperService {
  const ImageCropperService();

  Future<File?> cropProfileImage({required String sourcePath}) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Ajustar foto de perfil',
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Ajustar foto de perfil',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (cropped == null) return null;
    return File(cropped.path);
  }

  Future<File?> cropVehicleImage({required String sourcePath}) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Ajustar foto del vehiculo',
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Ajustar foto del vehiculo',
          aspectRatioLockEnabled: false,
        ),
      ],
    );

    if (cropped == null) return null;
    return File(cropped.path);
  }

  /// Imagen de un anuncio del carrusel: misma pantalla de recorte que la
  /// foto de perfil, con la proporción fija de la tarjeta (3:2). Sale en
  /// JPEG 95 y a lo sumo 2000 px: la compresión final a WebP la hace la
  /// capa de datos (`optimizarAWebP`) antes de subir.
  Future<File?> cropAnuncioImage({required String sourcePath}) => _recortar(
    sourcePath: sourcePath,
    titulo: 'Recortar anuncio',
    ratioX: 3,
    ratioY: 2,
  );

  /// Imagen de una promoción: cuadrada con guía circular (en la ventana se
  /// ve dentro de un círculo).
  Future<File?> cropPromocionImage({required String sourcePath}) => _recortar(
    sourcePath: sourcePath,
    titulo: 'Recortar imagen',
    ratioX: 1,
    ratioY: 1,
    circular: true,
  );

  Future<File?> _recortar({
    required String sourcePath,
    required String titulo,
    required double ratioX,
    required double ratioY,
    bool circular = false,
  }) async {
    final estilo = circular ? CropStyle.circle : CropStyle.rectangle;
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      maxWidth: 2000,
      maxHeight: 2000,
      aspectRatio: CropAspectRatio(ratioX: ratioX, ratioY: ratioY),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: titulo,
          lockAspectRatio: true,
          hideBottomControls: false,
          cropStyle: estilo,
        ),
        IOSUiSettings(
          title: titulo,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: estilo,
        ),
      ],
    );
    if (cropped == null) return null;
    return File(cropped.path);
  }
}
