import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'fake_client_auth_repository.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
import 'package:taxi_app/models/AuthModel.dart';
import 'package:taxi_app/domain/usecases/client_auth/sign_in_google_client_usecase.dart';

Widget buildTestAppFor(Widget child) {
  final fake = FakeClientAuthRepository();
  return MultiProvider(
    providers: [
      Provider<ClientAuthRepository>.value(value: fake),
      Provider<SignInGoogleClientUseCase>(
        create: (_) => SignInGoogleClientUseCase(fake),
      ),
      ChangeNotifierProvider(create: (_) => AuthViewModel(fake)),
    ],
    child: MaterialApp(home: child),
  );
}
