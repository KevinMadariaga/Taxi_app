import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/data/models/registro_cliente_model.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';


class RegistroClienteViewModel extends ChangeNotifier {
    // Método simple de encriptación (hash) usando SHA-256
    String _encryptPassword(String password) {
      // Usar la librería crypto para hash SHA-256
      // Requiere agregar 'crypto' en pubspec.yaml

      final bytes = utf8.encode(password);
      final digest = sha256.convert(bytes);
      return digest.toString();
    }
  bool loading = false;

  Future<String?> register(RegistroClienteModel model) async {
    loading = true;
    notifyListeners();

    try {
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;

      final userCredential = await auth.createUserWithEmailAndPassword(
        email: model.correo.trim(),
        password: model.password,
      );

      final encryptedPassword = _encryptPassword(model.password);
      await firestore.collection('cliente').doc(userCredential.user!.uid).set({
        'tipoUsuario': 'cliente',
        'clienteId': userCredential.user!.uid,
        'nombre': model.nombre.trim(),
        'apellido': model.apellido.trim(),
        'telefono': model.telefono.trim(),
        'correo': model.correo.trim(),
        'contraseña': encryptedPassword,
      });

      return null; // éxito
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Error al registrar usuario';
    } catch (e) {
      return 'Error al registrar: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
