import 'package:flutter/foundation.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
import 'package:taxi_app/data/repositories/client_auth/client_auth_repository_impl.dart';
import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/domain/usecases/client_auth/sign_in_google_client_usecase.dart';
import 'package:taxi_app/core/services/services.dart';

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

  String _toUiError(Object error) {
    final raw = error.toString();
    return raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }
}
