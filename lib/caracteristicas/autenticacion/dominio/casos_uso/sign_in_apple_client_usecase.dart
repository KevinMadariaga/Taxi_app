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
    final result = await _appleService.signInWithApple();
    if (result == null || result.userCredential.user == null) {
      throw StateError('El inicio de sesion con Apple fue cancelado.');
    }

    final firebaseUser = result.userCredential.user!;

    // Apple solo entrega el nombre la primera vez que autoriza la app.
    // Hay que usarlo ya (Directriz 4 de Apple) en vez de pedirlo de nuevo.
    final appleFullName = [result.givenName, result.familyName]
        .where((part) => (part ?? '').trim().isNotEmpty)
        .join(' ')
        .trim();

    var displayName = firebaseUser.displayName;
    if ((displayName ?? '').trim().isEmpty && appleFullName.isNotEmpty) {
      displayName = appleFullName;
      await firebaseUser.updateDisplayName(appleFullName);
    }

    final identity = AuthIdentityEntity(
      uid: firebaseUser.uid,
      displayName: displayName,
      email: firebaseUser.email,
      phoneNumber: firebaseUser.phoneNumber,
      photoUrl: firebaseUser.photoURL,
    );

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
