import 'package:flutter/foundation.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
import 'package:taxi_app/data/repositories/client_auth/client_auth_repository_impl.dart';
import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/domain/usecases/client_auth/sign_in_google_client_usecase.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/apple_sign_in_service.dart';
import 'package:taxi_app/domain/entities/client_user_entity.dart';

class HomeAuthController extends ChangeNotifier {
  HomeAuthController({
    SignInGoogleClientUseCase? signInGoogleClientUseCase,
    AuthService? authService,
    ClientAuthRepository? clientAuthRepository,
  }) : _signInGoogleClientUseCase =
           signInGoogleClientUseCase ??
           SignInGoogleClientUseCase(clientAuthRepository ?? ClientAuthRepositoryImpl()),
       _authService = authService ?? AuthService();

  final SignInGoogleClientUseCase _signInGoogleClientUseCase;
  final AuthService _authService;

  bool _loading = false;
  String? _errorMessage;

  bool get loading => _loading;
  String? get errorMessage => _errorMessage;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<AuthFlowResult?> loginWithGoogle() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _signInGoogleClientUseCase();
      await _authService.saveUserSession(role: 'cliente', isLoggedIn: true);
      return result;
    } catch (error) {
      _errorMessage = _toUiError(error);
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AuthFlowResult?> loginWithApple() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    final appleService = AppleSignInService();
    try {
      final userCred = await appleService.signInWithApple();
      if (userCred == null) {
        _errorMessage = 'Inicio de sesión con Apple cancelado.';
        return null;
      }

      // After Firebase sign-in, record session and map to AuthFlowResult
      await _authService.saveUserSession(role: 'cliente', isLoggedIn: true);

      // Build a minimal AuthFlowResult using firebase user
      final firebaseUser = userCred.user;
      if (firebaseUser == null) return null;

      final client = ClientUserEntity(
        id: firebaseUser.uid,
        nombre: firebaseUser.displayName ?? '',
        apellido: '',
        telefono: firebaseUser.phoneNumber ?? '',
        fotoUrl: firebaseUser.photoURL ?? '',
        rol: 'cliente',
        email: firebaseUser.email,
        isProfileComplete: false,
        createdAt: DateTime.now(),
      );

      final result = AuthFlowResult(
        destination: AuthFlowDestination.clientHome,
        user: client,
      );

      return result;
    } catch (error) {
      _errorMessage = _toUiError(error);
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _toUiError(Object error) {
    final raw = error.toString();
    return raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }
}
