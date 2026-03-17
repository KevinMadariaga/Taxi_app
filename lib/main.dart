import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/helper/firebase_helper.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/core/utils/app_dependencies.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/usuario_cliente/data/Auth.dart';
import 'package:taxi_app/screens/usuario_cliente/data/firebaseDB.dart';
import 'package:taxi_app/models/AuthModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaConductorViewModel.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/tracking_service.dart';

const SystemUiOverlayStyle _globalSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

/// Entry point for the Taxi App.
/// Initializes services, handles permissions, and launches the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_globalSystemOverlayStyle);
  await _initializeCoreServices();

  final dependencies = AppDependencies.initialize();
  runApp(MyApp(dependencies: dependencies));
}

/// Initializes Firebase, permissions, and notifications.
Future<void> _initializeCoreServices() async {
  await FirebaseHelper.initializeFirebase();

  if (!kReleaseMode && AppConstants.phoneAuthTestMode) {
    // In non-release environments this avoids Play Integrity/SafetyNet blocks
    // while phone auth is being configured in Firebase Console.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );

    if (kDebugMode) {
      debugPrint('FirebaseAuth test app verification is enabled (non-release).');
    }
  }

  await PermissionsHelper.requestAllPermissions();
  await NotificacionesServicio.instance.init();
  await initializeLocationNotificationChannel();
  await initializeTrackingNotificationChannel();
  await initializeBackgroundService();
}

/// Root widget for the Taxi App.
/// Sets up providers, theming, and navigation.
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) =>
                  AuthViewModel(AuthRepository(FirebaseDataSource())),
            ),
            ChangeNotifierProvider(create: (_) => RutaConductorViewModel()),
            ChangeNotifierProvider(create: (_) => Rutaclienteviewmodel()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: AppConstants.appTitle,
            theme: AppThemeConfig.lightTheme,
            initialRoute: AppRoutes.splash,
            onGenerateRoute: (settings) {
              return AppRoutes.onGenerateRoute(settings, dependencies);
            },
            builder: (context, child) {
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: _globalSystemOverlayStyle,
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        );
      },
    );
  }
}
