import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class SendClientPhoneOtpParams {
  const SendClientPhoneOtpParams({
    required this.phoneNumber,
    this.forceResendingToken,
  });

  final String phoneNumber;
  final int? forceResendingToken;
}

class SendClientPhoneOtpUseCase {
  SendClientPhoneOtpUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<PhoneVerificationResult> call(SendClientPhoneOtpParams params) {
    return _repository.sendPhoneOtp(
      phoneNumber: params.phoneNumber,
      forceResendingToken: params.forceResendingToken,
    );
  }
}
