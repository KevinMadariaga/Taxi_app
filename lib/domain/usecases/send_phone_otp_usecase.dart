import 'package:taxi_app/domain/models/phone_verification_result.dart';
import 'package:taxi_app/domain/repositories/auth_repository.dart';

class SendPhoneOtpParams {
  const SendPhoneOtpParams({
    required this.phoneNumber,
    this.forceResendingToken,
  });

  final String phoneNumber;
  final int? forceResendingToken;
}

class SendPhoneOtpUseCase {
  SendPhoneOtpUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<PhoneVerificationResult> call(SendPhoneOtpParams params) {
    return _authRepository.sendPhoneOtp(
      phoneNumber: params.phoneNumber,
      forceResendingToken: params.forceResendingToken,
    );
  }
}
