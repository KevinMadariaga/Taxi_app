import 'package:flutter/foundation.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/data/Auth.dart';

/// ViewModel para gestionar la autenticación de usuario (login/logout, estado y errores).
class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  AuthViewModel(this._authRepository);

  String _email = '';
  String _password = '';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAuthenticated = false;

  // Getters públicos
  String get email => _email;
  String get password => _password;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _isAuthenticated;

  void setEmail(String value) {
    _email = value;
    notifyListeners();
  }

  void setPassword(String value) {
    _password = value;
    notifyListeners();
  }

  /// Realiza login y detecta el rol del usuario (cliente/conductor).
  Future<void> login() async {
    if (_email.isEmpty || _password.isEmpty) {
      _errorMessage = 'Campos obligatorios';
      notifyListeners();
      return;
    }
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _authRepository.login(_email, _password);
      _isAuthenticated = true;

      // Detectar rol dinámicamente
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      String role = 'cliente';
      if (uid.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        final conductorDoc = await firestore.collection('conductor').doc(uid).get();
        if (conductorDoc.exists) {
          role = 'conductor';
        } else {
          final clienteDoc = await firestore.collection('cliente').doc(uid).get();
          if (clienteDoc.exists) {
            role = 'cliente';
          }
        }
      }
      await SessionHelper.saveSession(role, uid);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Credenciales inválidas';
      _isAuthenticated = false;
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpia el estado de autenticación (por ejemplo, al cerrar sesión).
  void clearAuthenticated() {
    if (_isAuthenticated) {
      _isAuthenticated = false;
      notifyListeners();
    }
  }

  /// Realiza logout y limpia la sesión guardada.
  Future<void> logout() async {
    try {
      _isLoading = true;
      notifyListeners();
      await _authRepository.logout();
      await SessionHelper.clearSession();
      _isAuthenticated = false;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al cerrar sesión';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
