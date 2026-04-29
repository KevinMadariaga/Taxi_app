import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:taxi_app/data/models/registro_cliente_model.dart';

class RegistroClienteViewModel extends ChangeNotifier {
  bool _loading = false;

  static const int _maxBytes = 100 * 1024;

  bool get loading => _loading;

  Future<bool> emailExiste(String email) async {
    final snap = await FirebaseFirestore.instance
        .collection('cliente')
        .where('correo', isEqualTo: email.trim())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

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

  /// Registra al usuario y opcionalmente sube `profileImage` a Firebase Storage.
  /// Devuelve `null` en éxito o un mensaje de error.
  Future<String?> register(
    RegistroClienteModel model, [
    File? profileImage,
  ]) async {
    _loading = true;
    notifyListeners();
    try {
      // Create auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: model.correo.trim(),
        password: model.password,
      );

      final uid = cred.user?.uid;
      String? photoUrl;

      if (uid != null) {
        // Si hay imagen, subirla primero y obtener URL
        if (profileImage != null) {
          final bytes = await _compressWebPUnder100Kb(profileImage);
          final storageRef = FirebaseStorage.instance.ref().child(
            'cliente/$uid/profile.webp',
          );
          final uploadTask = await storageRef.putData(
            bytes,
            SettableMetadata(contentType: 'image/webp'),
          );
          // Asegurarse de que la subida terminó correctamente
          if (uploadTask.state == TaskState.success) {
            photoUrl = await storageRef.getDownloadURL();
          }
        }

        final data = {
          'tipoUsuario': 'cliente',
          'clienteId': uid,
          'nombre': model.nombre.trim(),
          'telefono': model.telefono.trim(),
          'correo': model.correo.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        };

        if (photoUrl != null) {
          data['fotoUrl'] = photoUrl;
        }

        await FirebaseFirestore.instance
            .collection('cliente')
            .doc(uid)
            .set(data);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Error de autenticación';
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
