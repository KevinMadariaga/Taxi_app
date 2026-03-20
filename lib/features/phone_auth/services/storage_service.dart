import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class StorageService {
  StorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static const int _maxBytes = 100 * 1024;

  Future<Uint8List> _compressWebPUnder100Kb(File file) async {
    final original = await file.readAsBytes();
    Uint8List best = Uint8List.fromList(original);

    final attempts = <Map<String, int>>[
      {'q': 80, 'w': 0},
      {'q': 70, 'w': 0},
      {'q': 60, 'w': 1280},
      {'q': 50, 'w': 1080},
      {'q': 45, 'w': 900},
      {'q': 40, 'w': 720},
      {'q': 35, 'w': 640},
      {'q': 30, 'w': 560},
      {'q': 25, 'w': 480},
    ];

    for (final a in attempts) {
      try {
        final q = a['q'] ?? 70;
        final w = a['w'] ?? 0;
        final bytes = w > 0
            ? await FlutterImageCompress.compressWithList(
                original,
                quality: q,
                format: CompressFormat.webp,
                minWidth: w,
                minHeight: w,
              )
            : await FlutterImageCompress.compressWithList(
                original,
                quality: q,
                format: CompressFormat.webp,
              );
        if (bytes.isEmpty) continue;

        final current = Uint8List.fromList(bytes);
        if (best.isEmpty || current.length < best.length) {
          best = current;
        }
        if (current.length <= _maxBytes) {
          return current;
        }
      } catch (_) {}
    }

    return best;
  }

  String _normalizeWebPPath(String path) {
    final hasExt = RegExp(r'\.[a-zA-Z0-9]+$').hasMatch(path);
    if (!hasExt) return '$path.webp';
    return path.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.webp');
  }

  Future<String> uploadImage({required File file, required String path}) async {
    final bytes = await _compressWebPUnder100Kb(file);
    final webpPath = _normalizeWebPPath(path);
    final ref = _storage.ref().child(webpPath);
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/webp'),
    );
    return task.ref.getDownloadURL();
  }
}
