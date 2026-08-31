import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/network_error_helper.dart';

class ClientAuthFirebaseDataSource {
  ClientAuthFirebaseDataSource({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  Future<AuthIdentityEntity?> signInWithGoogle() async {
    try {
      // Ensure account chooser is shown when user wants to pick a different
      // Google account. Signing out any previous GoogleSignIn session forces
      // the system picker on subsequent `signIn()` calls.
      if (_googleSignIn.currentUser != null) {
        try {
          await _googleSignIn.signOut();
        } catch (e, st) {
          ErrorReporter.report(
            e,
            st,
            reason: 'client_auth_firebase_datasource',
          );
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'client_auth_firebase_datasource');
    }

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        throw StateError('No fue posible autenticar el usuario con Google.');
      }

      return AuthIdentityEntity(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        phoneNumber: user.phoneNumber,
        photoUrl: user.photoURL,
      );
    } catch (e, st) {
      // En algunos dispositivos Android `google_sign_in` no devuelve null al
      // cancelar, sino que lanza `PlatformException(sign_in_canceled)`. Eso
      // terminaba reportado a Crashlytics y mostrado como error rojo, cuando
      // el usuario simplemente cerró el selector de cuentas. Se trata igual
      // que el null: sin identidad, y el caso de uso lo convierte en
      // `AuthCancelledException`.
      if (_esCancelacionDelUsuario(e)) return null;
      ErrorReporter.report(e, st, reason: 'client_auth_firebase_datasource');
      throw StateError(_mapGoogleSignInError(e));
    }
  }

  static bool _esCancelacionDelUsuario(Object error) {
    if (error is! PlatformException) return false;
    final code = error.code.toLowerCase();
    return code.contains('canceled') || code.contains('cancelled');
  }

  /// Traduce excepciones técnicas del inicio de sesión con Google (códigos de
  /// `PlatformException` de Google Play Services, `FirebaseAuthException`,
  /// fallas de red) a un mensaje en español entendible. Nunca se debe dejar
  /// pasar el `toString()` crudo de la excepción hasta la UI.
  String _mapGoogleSignInError(Object error) {
    if (esErrorDeConexion(error)) {
      return 'No tienes conexión a internet. Verifica tu conexión e intenta de nuevo.';
    }
    if (error is FirebaseAuthException) {
      if (error.code == 'account-exists-with-different-credential') {
        return 'Ya existe una cuenta con este correo usando otro método de inicio de sesión.';
      }
      return 'No se pudo completar el inicio de sesión con Google. Intenta de nuevo.';
    }
    return 'No se pudo iniciar sesión con Google. Intenta de nuevo.';
  }

}
