import 'package:taxi_app/domain/models/phone_verification_result.dart';

abstract class AuthRepository {
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  });
}
