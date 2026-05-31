import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ClientProfileImageDataSource {
  ClientProfileImageDataSource({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const int _maxBytes = 100 * 1024;
  static const List<int> _qualities = <int>[80, 75, 70];
  static const List<int> _sizes = <int>[512, 480, 440, 400, 360, 320];

  Future<String> uploadProfileImage({
    required String uid,
    required File file,
  }) async {
    final optimized = await _compressToWebP(file);

    final ref = _storage.ref().child(
      'usuarios/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp',
    );

    final task = await ref.putData(
      optimized,
      SettableMetadata(contentType: 'image/webp'),
    );

    return task.ref.getDownloadURL();
  }

  Future<Uint8List> _compressToWebP(File file) async {
    final source = await file.readAsBytes();

    Uint8List? best;
    for (final quality in _qualities) {
      for (final size in _sizes) {
        final compressed = await FlutterImageCompress.compressWithList(
          source,
          format: CompressFormat.webp,
          quality: quality,
          minWidth: size,
          minHeight: size,
          keepExif: false,
        );

        if (compressed.isEmpty) {
          continue;
        }

        final candidate = Uint8List.fromList(compressed);
        if (best == null || candidate.length < best.length) {
          best = candidate;
        }

        if (candidate.length <= _maxBytes) {
          return candidate;
        }
      }
    }

    throw StateError(
      'La imagen supera 100 KB despues de optimizarla. Intenta con otra foto.',
    );
  }
}
