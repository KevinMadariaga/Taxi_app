import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';

abstract class AuthRepository {
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  });
}
