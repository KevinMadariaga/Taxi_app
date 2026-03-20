import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';

class VerifyClientPhoneOtpParams {
  const VerifyClientPhoneOtpParams({
    required this.verificationId,
    required this.otpCode,
    required this.phoneNumber,
  });

  final String verificationId;
  final String otpCode;
  final String phoneNumber;
}

class VerifyClientPhoneOtpUseCase {
  VerifyClientPhoneOtpUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<AuthFlowResult> call(VerifyClientPhoneOtpParams params) async {
    final identity = await _repository.verifyPhoneOtp(
      verificationId: params.verificationId,
      otpCode: params.otpCode,
    );

    final resolvedPhone = _normalizeToTenDigits(
      (identity.phoneNumber ?? params.phoneNumber).trim(),
    );

    final user = await _repository.ensureClientUserForPhone(
      uid: identity.uid,
      phoneNumber: resolvedPhone,
    );

    return AuthFlowResult(
      destination: user.isProfileComplete
          ? AuthFlowDestination.clientHome
          : AuthFlowDestination.completeProfile,
      user: user,
    );
  }

  String _normalizeToTenDigits(String phone) {
    if (phone.trim().isEmpty) {
      return '';
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 10) {
      return digits;
    }
    return digits.substring(digits.length - 10);
  }
}
