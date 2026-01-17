import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_app/data/models/registro_cliente_model.dart';


class RegistroClienteViewModel extends ChangeNotifier {
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

      await firestore.collection('cliente').doc(userCredential.user!.uid).set({
        'tipoUsuario': 'cliente',
        'clienteId': userCredential.user!.uid,
        'nombre': model.nombre.trim(),
        'telefono': model.telefono.trim(),
        'correo': model.correo.trim(),
        'contraseña': model.password,
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
