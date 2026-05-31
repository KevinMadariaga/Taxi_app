import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/firebase_auth_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._firebaseAuthDataSource);

  final FirebaseAuthDataSource _firebaseAuthDataSource;

  @override
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) {
    return _firebaseAuthDataSource.sendPhoneOtp(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
    );
  }
}
