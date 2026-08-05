import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/network_error_helper.dart';

/// Apple only returns [givenName]/[familyName] on the user's first
/// authorization. Firebase does not populate `User.displayName` from
/// this data, so callers must capture it here or lose it permanently.
class AppleSignInResult {
  const AppleSignInResult({
    required this.userCredential,
    this.givenName,
    this.familyName,
  });

  final UserCredential userCredential;
  final String? givenName;
  final String? familyName;
}

class AppleSignInService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Performs Sign in with Apple and returns the Firebase [UserCredential]
  /// plus the name Apple shared, or null if cancelled/failed.
  Future<AppleSignInResult?> signInWithApple() async {
    try {
      // Request credential from Apple
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Create an `OAuthCredential` for Firebase
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in with Firebase
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      return AppleSignInResult(
        userCredential: userCredential,
        givenName: appleCredential.givenName,
        familyName: appleCredential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e, st) {
      // Cancelar el sheet de Apple no es un error: mismo comportamiento que
      // Google (que simplemente devuelve `null` sin lanzar excepción).
      if (e.code == AuthorizationErrorCode.canceled) return null;
      ErrorReporter.report(e, st, reason: 'apple_sign_in_service');
      throw StateError('No se pudo iniciar sesión con Apple. Intenta de nuevo.');
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'apple_sign_in_service');
      if (esErrorDeConexion(e)) {
        throw StateError(
          'No tienes conexión a internet. Verifica tu conexión e intenta de nuevo.',
        );
      }
      throw StateError('No se pudo iniciar sesión con Apple. Intenta de nuevo.');
    }
  }
}
