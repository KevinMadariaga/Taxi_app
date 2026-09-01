import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_cancelled_exception.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class SignInGoogleClientUseCase {
  SignInGoogleClientUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<AuthFlowResult> call() async {
    final identity = await _repository.signInWithGoogle();
    if (identity == null || identity.uid.isEmpty) {
      throw const AuthCancelledException('google');
    }

    final user = await _repository.ensureClientUserForGoogle(
      uid: identity.uid,
      displayName: identity.displayName,
      email: identity.email,
      photoUrl: null,
    );

    // El nombre guardado en Firestore manda sobre el de Gmail: si el usuario
    // ya había editado su nombre, esto corrige el `displayName` de Auth (que
    // se había quedado congelado con el de Google) para que el resto de la
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
