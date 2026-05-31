import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/firebase_auth_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/send_phone_otp_usecase.dart';

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
