import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_cancelled_exception.dart';
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
      throw const AuthCancelledException('apple');
    }

    final firebaseUser = result.userCredential.user!;

    // Apple solo entrega el nombre la primera vez que autoriza la app.
    // Hay que usarlo ya (Directriz 4 de Apple) en vez de pedirlo de nuevo.
    final appleFullName = [
      result.givenName,
      result.familyName,
    ].where((part) => (part ?? '').trim().isNotEmpty).join(' ').trim();

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

    // El nombre guardado en Firestore manda sobre el de Apple: si el usuario
    // ya había editado su nombre, esto corrige el `displayName` de Auth (que
    // se había quedado congelado con el de Apple) para que el resto de la
    // app deje de caer en el fallback viejo.
    final nombreCompleto = '${user.nombre} ${user.apellido}'.trim();
    await _repository.syncAuthDisplayName(nombreCompleto);

    return AuthFlowResult(
      destination: user.isProfileComplete
          ? AuthFlowDestination.clientHome
          : AuthFlowDestination.completeProfile,
      user: user,
    );
  }
}
