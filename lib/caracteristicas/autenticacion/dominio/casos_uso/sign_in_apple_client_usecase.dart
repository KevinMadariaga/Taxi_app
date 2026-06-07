import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/core/services/apple_sign_in_service.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';

class SignInAppleClientUseCase {
  SignInAppleClientUseCase(this._repository, {AppleSignInService? appleService})
    : _appleService = appleService ?? AppleSignInService();

  final ClientAuthRepository _repository;
  final AppleSignInService _appleService;

  Future<AuthFlowResult> call() async {
    final userCred = await _appleService.signInWithApple();
    if (userCred == null || userCred.user == null) {
      throw StateError('El inicio de sesion con Apple fue cancelado.');
    }

    final firebaseUser = userCred.user!;

    final identity = AuthIdentityEntity(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName,
      email: firebaseUser.email,
      phoneNumber: firebaseUser.phoneNumber,
      photoUrl: firebaseUser.photoURL,
    );

    final user = await _repository.ensureClientUserForGoogle(
      uid: identity.uid,
      displayName: identity.displayName,
      email: identity.email,
      photoUrl: identity.photoUrl,
    );

    return AuthFlowResult(
      destination: user.isProfileComplete
          ? AuthFlowDestination.clientHome
          : AuthFlowDestination.completeProfile,
      user: user,
    );
  }
}
