import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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
  }

  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    final completer = Completer<PhoneVerificationResult>();

    if (!kReleaseMode && AppConstants.phoneAuthTestMode) {
      await _auth.setSettings(appVerificationDisabledForTesting: true);
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (_) {},
      verificationFailed: (error) {
        if (completer.isCompleted) return;
        completer.completeError(StateError(_mapPhoneAuthError(error)));
      },
      codeSent: (verificationId, resendToken) {
        if (completer.isCompleted) return;
        completer.complete(
          PhoneVerificationResult(
            verificationId: verificationId,
            resendToken: resendToken,
          ),
        );
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (completer.isCompleted) return;
        completer.complete(
          PhoneVerificationResult(verificationId: verificationId),
        );
      },
    );

    return completer.future;
  }

  Future<AuthIdentityEntity> verifyPhoneOtp({
    required String verificationId,
    required String otpCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otpCode,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw StateError('No fue posible autenticar al usuario.');
      }

      return AuthIdentityEntity(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        phoneNumber: user.phoneNumber,
      );
    } on FirebaseAuthException catch (error) {
      final message = _mapVerifyError(error);
      throw StateError(message);
    }
  }

  String _mapVerifyError(FirebaseAuthException error) {
    final raw = (error.message ?? '').toLowerCase();

    if (error.code == 'invalid-verification-code' ||
        raw.contains('invalid verification code') ||
        error.code == 'invalid-verification-id') {
      return 'El codigo ingresado es incorrecto o ha expirado.';
    }

    if (error.code == 'session-expired' || raw.contains('expired')) {
      return 'El codigo de verificacion ha expirado. Solicita uno nuevo.';
    }

    if (error.code == 'too-many-requests') {
      return 'Demasiados intentos. Espera unos minutos e intenta nuevamente.';
    }

    if (error.code == 'quota-exceeded') {
      return 'Se alcanzo el limite de SMS de Firebase para este proyecto.';
    }

    if (error.code == 'network-request-failed') {
      return 'Fallo de red. Comprueba tu conexión e intenta otra vez.';
    }

    return error.message ?? 'No fue posible verificar el codigo.';
  }

  String _mapPhoneAuthError(FirebaseAuthException error) {
    final rawMessage = (error.message ?? '').toLowerCase();

    final isAppAuthConfigError =
        error.code == 'app-not-authorized' ||
        error.code == 'invalid-app-credential' ||
        rawMessage.contains('missing a valid app identifier') ||
        rawMessage.contains('play integrity checks') ||
        rawMessage.contains('recaptcha checks were unsuccessful') ||
        rawMessage.contains('play_integrity_token') ||
        rawMessage.contains('not authorized to use firebase authentication') ||
        rawMessage.contains('sha-1') ||
        rawMessage.contains('sha-256');

    if (isAppAuthConfigError) {
      return 'Esta aplicacion aun no esta autorizada para Autenticacion Telefonica. '
          'Configura package name, SHA-1 y SHA-256 en Firebase Console.';
    }

    if (error.code == 'invalid-phone-number') {
      return 'El numero de telefono no es valido.';
    }

    if (error.code == 'too-many-requests') {
      return 'Demasiados intentos. Espera unos minutos e intenta nuevamente.';
    }

    if (error.code == 'quota-exceeded') {
      return 'Se alcanzo el limite de SMS de Firebase para este proyecto.';
    }

    return error.message ?? 'No fue posible enviar el codigo de verificacion.';
  }
}
