import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class SignInGoogleClientUseCase {
  SignInGoogleClientUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<AuthFlowResult> call() async {
    final identity = await _repository.signInWithGoogle();
    if (identity == null || identity.uid.isEmpty) {
      throw StateError('El inicio de sesion con Google fue cancelado.');
    }

    final user = await _repository.ensureClientUserForGoogle(
      uid: identity.uid,
      displayName: identity.displayName,
      email: identity.email,
      photoUrl: null,
    );

    return AuthFlowResult(
      destination: user.isProfileComplete
          ? AuthFlowDestination.clientHome
          : AuthFlowDestination.completeProfile,
      user: user,
    );
  }
}
