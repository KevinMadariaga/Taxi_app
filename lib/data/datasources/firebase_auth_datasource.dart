import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/domain/models/phone_verification_result.dart';

class FirebaseAuthDataSource {
  FirebaseAuthDataSource({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

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
        final message = _mapPhoneAuthError(error);
        completer.completeError(StateError(message));
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
          'Configura en Firebase Console el package name, SHA-1 y SHA-256 del proyecto Android '
          'y prueba en dispositivo fisico con Google Play Services.';
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
