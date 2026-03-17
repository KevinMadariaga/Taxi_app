import 'package:flutter/material.dart';
import 'package:taxi_app/presentation/screens/splash/splash_view.dart';

@Deprecated('Usa SplashView desde presentation/screens/splash.')
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.nextScreen});

  final Widget? nextScreen;

  @override
  Widget build(BuildContext context) {
    return const SplashView();
  }
}
