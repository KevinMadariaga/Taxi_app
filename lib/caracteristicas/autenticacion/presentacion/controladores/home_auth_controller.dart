import 'package:flutter/foundation.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/client_auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_apple_client_usecase.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/utils/network_error_helper.dart';

class HomeAuthController extends ChangeNotifier {
  HomeAuthController({
    SignInGoogleClientUseCase? signInGoogleClientUseCase,
    SignInAppleClientUseCase? signInAppleClientUseCase,
    AuthService? authService,
    ClientAuthRepository? clientAuthRepository,
  }) : _signInGoogleClientUseCase =
           signInGoogleClientUseCase ??
           SignInGoogleClientUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           ),
       _signInAppleClientUseCase =
           signInAppleClientUseCase ??
           SignInAppleClientUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           ),
       _authService = authService ?? AuthService();

  final SignInGoogleClientUseCase _signInGoogleClientUseCase;
  final SignInAppleClientUseCase _signInAppleClientUseCase;
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

    try {
      final result = await _signInAppleClientUseCase();
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

  /// Última barrera antes de mostrar un error en la UI: nunca debe llegar
  /// texto crudo de una excepción (nombres de clase, códigos de Play
  /// Services, "null, null", etc.) — si algo no vino ya traducido desde el
  /// datasource, se cae a un mensaje genérico en español.
  String _toUiError(Object error) {
    if (esErrorDeConexion(error)) {
      return 'No tienes conexión a internet. Verifica tu conexión e intenta de nuevo.';
    }

    final raw = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();

    final pareceCrudo =
        raw.isEmpty ||
        raw.contains('PlatformException') ||
        raw.contains('Instance of ') ||
        raw.contains('null, null') ||
        RegExp(r'^[A-Za-z_]+Exception').hasMatch(raw);

    if (pareceCrudo) {
      return 'No se pudo iniciar sesión. Intenta de nuevo en unos minutos.';
    }
    return raw;
  }
}
