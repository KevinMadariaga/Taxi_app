import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/utils/app_dependencies.dart';
import 'package:taxi_app/presentation/screens/splash/splash_view.dart';
import 'package:taxi_app/presentation/viewmodels/login/login_viewmodel.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/screens/home_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings,
    AppDependencies dependencies,
  ) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => SplashViewModel(),
            child: const SplashView(),
          ),
        );
      case login:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => LoginViewModel(
              sendPhoneOtpUseCase: dependencies.sendPhoneOtpUseCase,
            ),
            child: const HomeView(),
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Ruta no encontrada')),
            body: Center(
              child: Text('No existe la ruta: ${settings.name}'),
            ),
          ),
        );
    }
  }
}
