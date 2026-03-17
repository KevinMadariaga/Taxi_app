import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/phone_code_result_model.dart';

class PhoneAuthService {
  PhoneAuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<PhoneCodeResultModel> sendCode({
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    final completer = Completer<PhoneCodeResultModel>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (_) {},
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneCodeResultModel(
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneCodeResultModel(verificationId: verificationId),
          );
        }
      },
    );

    return completer.future;
  }

  Future<UserCredential> verifyCode({
    required String verificationId,
    required String otpCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otpCode,
    );
    return _auth.signInWithCredential(credential);
  }
}
