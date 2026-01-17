import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../registro_cliente_model.dart';

class RegistroClienteViewModel extends ChangeNotifier {
  bool _loading = false;

  bool get loading => _loading;

  /// Registra al usuario y opcionalmente sube `profileImage` a Firebase Storage.
  /// Devuelve `null` en éxito o un mensaje de error.
  Future<String?> register(RegistroClienteModel model, [File? profileImage]) async {
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
          final storageRef = FirebaseStorage.instance.ref().child('cliente/$uid/profile.jpg');
          final uploadTask = await storageRef.putFile(profileImage);
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

        await FirebaseFirestore.instance.collection('cliente').doc(uid).set(data);
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
