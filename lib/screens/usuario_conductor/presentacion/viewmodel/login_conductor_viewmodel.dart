import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/models/LoginConductorModel.dart';

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

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _buscarConductorPorCorreo(String correo) async {
    final qLegacy = await _firestore
        .collection('conductor')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();
    if (qLegacy.docs.isNotEmpty) return qLegacy.docs.first;

    final qAdmin = await _firestore
        .collection('conductores')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();
    if (qAdmin.docs.isNotEmpty) return qAdmin.docs.first;

    return null;
  }

  Future<void> _sincronizarDocConductorConUidAuth({
    required String authUid,
    required Map<String, dynamic> source,
    required String correo,
    required String password,
  }) async {
    await _firestore.collection('conductor').doc(authUid).set({
      'tipoUsuario': 'conductor',
      'conductorId': authUid,
      'nombre': (source['nombre'] ?? '').toString(),
      'telefono': (source['telefono'] ?? '').toString(),
      'placa': (source['placa'] ?? '').toString(),
      'foto': (source['fotoConductor'] ?? source['foto'] ?? '').toString(),
      'fotoConductor': (source['fotoConductor'] ?? '').toString(),
      'fotoVehiculo': (source['fotoVehiculo'] ?? '').toString(),
      'adminId': (source['adminId'] ?? '').toString(),
      'estado': (source['estado'] ?? 'activo').toString(),
      'correo': correo,
      'passwordLogin': password,
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('conductores').doc(authUid).set({
      'idConductor': authUid,
      'nombre': (source['nombre'] ?? '').toString(),
      'telefono': (source['telefono'] ?? '').toString(),
      'placa': (source['placa'] ?? '').toString(),
      'fotoConductor': (source['fotoConductor'] ?? source['foto'] ?? '')
          .toString(),
      'fotoVehiculo': (source['fotoVehiculo'] ?? '').toString(),
      'adminId': (source['adminId'] ?? '').toString(),
      'estado': (source['estado'] ?? 'activo').toString(),
      'correo': correo,
      'passwordLogin': password,
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return false;
    isLoading.value = true;
    error.value = null;
    try {
      final email = emailController.text.trim().toLowerCase();
      final pass = passwordController.text.trim();

      final doc = await _buscarConductorPorCorreo(email);
      if (doc == null) {
        error.value = 'Este usuario no está permitido';
        conductor.value = null;
        return false;
      }

      final data = doc.data();
      final estado = (data['estado'] ?? 'activo').toString().toLowerCase();
      if (estado != 'activo') {
        error.value = 'Tu cuenta está inactiva. Contacta al administrador.';
        conductor.value = null;
        return false;
      }

      final storedPass = (data['passwordLogin'] ?? '').toString();
      if (storedPass.isNotEmpty && storedPass != pass) {
        error.value = 'Credenciales inválidas';
        conductor.value = null;
        return false;
      }

      // Mapear documento a modelo LoginConductorModel
      conductor.value = LoginConductorModel.fromMap(doc.id, data);

      try {
        await _auth.signInWithEmailAndPassword(email: email, password: pass);
      } on FirebaseAuthException catch (e) {
        // Para conductores creados desde panel admin sin usuario Auth previo.
        if (e.code == 'user-not-found' ||
            e.code == 'invalid-credential' ||
            e.code == 'wrong-password') {
          final created = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: pass,
          );
          if (created.user == null) {
            error.value = 'No se pudo iniciar sesión del conductor.';
            return false;
          }
        } else {
          rethrow;
        }
      }

      final authUid = _auth.currentUser?.uid;
      if (authUid == null || authUid.isEmpty) {
        error.value = 'No se pudo validar la sesión del conductor.';
        return false;
      }

      await _sincronizarDocConductorConUidAuth(
        authUid: authUid,
        source: data,
        correo: email,
        password: pass,
      );

      // Guardar estado de sesión y rol
      await SessionHelper.saveSession('conductor', authUid);
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
