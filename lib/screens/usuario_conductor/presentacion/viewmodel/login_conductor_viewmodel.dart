import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/model/login_conductor_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/services/ubicacion_servicio.dart';

class LoginConductorViewModel {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<LoginConductorModel?> conductor = ValueNotifier(null);

  LoginConductorViewModel({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  // Exponer usuario actual de forma segura
  User? get currentUser => _auth.currentUser;

  Future<bool> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return false;
    isLoading.value = true;
    error.value = null;
    try {
      final result = await _firestore
          .collection('conductor')
          .where('correo', isEqualTo: emailController.text.trim())
          .get();
      if (result.docs.isEmpty) {
        error.value = 'Este usuario no está permitido';
        conductor.value = null;
        return false;
      }
      // Mapear documento a modelo LoginConductorModel
      final doc = result.docs.first;
      final data = doc.data();
      conductor.value = LoginConductorModel.fromMap(doc.id, data);
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      // Guardar estado de sesión y rol
      await SessionHelper.saveSession('conductor', conductor.value?.id ?? '');
      // Obtener ubicación actual vía GPS y guardarla en Firestore bajo conductor/{uid}
      final uid = _auth.currentUser?.uid ?? conductor.value?.id;
      if (uid != null && uid.isNotEmpty) {
        try {
          await UbicacionService().obtenerYEnviarUbicacion(onResult: (LatLng loc) async {
            try {
              await FirebaseFirestore.instance.collection('conductor').doc(uid).set({
                'ubicacion': {'lat': loc.latitude, 'lng': loc.longitude},
                'lastLocationAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (_) {}
          });
        } catch (_) {}
      }
      return true;
    } on FirebaseAuthException catch (e) {
      error.value = e.message ?? e.code;
      return false;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    isLoading.dispose();
    error.dispose();
    conductor.dispose();
  }
}
