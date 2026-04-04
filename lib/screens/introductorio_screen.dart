import 'package:flutter/material.dart';
import 'package:taxi_app/screens/home_screen.dart';

@Deprecated('Usa LoginView desde presentation/screens/login.')
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.onFinish});

  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    return HomeView(onLegacyFinish: onFinish);
  }
}
