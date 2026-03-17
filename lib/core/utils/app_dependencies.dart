import 'package:taxi_app/data/datasources/firebase_auth_datasource.dart';
import 'package:taxi_app/data/repositories/auth_repository_impl.dart';
import 'package:taxi_app/domain/usecases/send_phone_otp_usecase.dart';

class AppDependencies {
  const AppDependencies({required this.sendPhoneOtpUseCase});

  final SendPhoneOtpUseCase sendPhoneOtpUseCase;

  factory AppDependencies.initialize() {
    final authDataSource = FirebaseAuthDataSource();
    final authRepository = AuthRepositoryImpl(authDataSource);

    return AppDependencies(
      sendPhoneOtpUseCase: SendPhoneOtpUseCase(authRepository),
    );
  }
}
