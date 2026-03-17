import 'package:taxi_app/data/datasources/firebase_auth_datasource.dart';
import 'package:taxi_app/domain/models/phone_verification_result.dart';
import 'package:taxi_app/domain/repositories/auth_repository.dart';

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
