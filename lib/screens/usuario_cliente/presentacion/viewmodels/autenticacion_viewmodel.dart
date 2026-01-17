import 'package:flutter/foundation.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/data/autenticacion.dart';


class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  AuthViewModel(this._authRepository);

  String _email = '';
  String _password = '';
  bool isLoading = false;
  String? errorMessage;
  bool isAuthenticated = false;

  void setEmail(String value) {
    _email = value;
  }

  void setPassword(String value) {
    _password = value;
  }

  Future<void> login() async {
    if (_email.isEmpty || _password.isEmpty) {
      errorMessage = 'Campos obligatorios';
      notifyListeners();
      return;
    }

    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();

      await _authRepository.login(_email, _password);
      isAuthenticated = true;

      // Detectar dinámicamente el rol del usuario en base a sus colecciones
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      String role = 'cliente';
      try {
        if (uid.isNotEmpty) {
          final firestore = FirebaseFirestore.instance;

          // Primero verificamos si existe en la colección 'conductor'
          final conductorDoc = await firestore.collection('conductor').doc(uid).get();
          if (conductorDoc.exists) {
            role = 'conductor';
          } else {
            // Si no es conductor, verificamos si existe en la colección 'cliente'
            final clienteDoc = await firestore.collection('cliente').doc(uid).get();
            if (clienteDoc.exists) {
              role = 'cliente';
            }
          }
        }
      } catch (_) {
        // Si falla la detección, dejamos 'cliente' por defecto
      }

      // Guardar sesión mínima (role + uid) con el rol detectado
      await SessionHelper.saveSession(role, uid);
      notifyListeners();
    } catch (e) {
      errorMessage = 'Credenciales inválidas';
      isAuthenticated = false;
      notifyListeners();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void clearAuthenticated() {
    if (isAuthenticated) {
      isAuthenticated = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      isLoading = true;
      notifyListeners();
      await _authRepository.logout();
      // Clear saved session
      await SessionHelper.clearSession();
      isAuthenticated = false;
      errorMessage = null;
    } catch (e) {
      errorMessage = 'Error al cerrar sesión';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
