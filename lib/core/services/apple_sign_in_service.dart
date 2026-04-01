import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppleSignInService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Performs Sign in with Apple and returns a Firebase [UserCredential]
  /// or null if the user cancelled or the operation failed.
  Future<UserCredential?> signInWithApple() async {
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
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }
}
