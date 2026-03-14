import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/firebase_helper.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/screens/splash_screen.dart';
import 'package:taxi_app/screens/introductorio_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/data/Auth.dart';
import 'package:taxi_app/screens/usuario_cliente/data/firebaseDB.dart';
import 'package:taxi_app/models/AuthModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/RutaConductorViewModel.dart';
import 'package:taxi_app/services/auth_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:taxi_app/theme/app_theme.dart';
 
/// Entry point for the Taxi App.
/// Initializes services, handles permissions, and launches the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  await _initializeAppServices();
  await initializeBackgroundService();
  final initialScreen = await _getInitialScreen();
  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;
  runApp(MyApp(
    initialScreen: initialScreen,
    prefs: prefs,
    seenOnboarding: seenOnboarding,
  ));
}

/// Initializes Firebase, permissions, and notifications.
Future<void> _initializeAppServices() async {
  await FirebaseHelper.initializeFirebase();
  await PermissionsHelper.requestAllPermissions();
  await NotificacionesServicio.instance.init();
  await initializeLocationNotificationChannel(); // Canal de notificación para tracking
  await initializeTrackingNotificationChannel(); // Canal de notificación para background service
}

/// Determines the initial screen based on authentication state.
Future<Widget> _getInitialScreen() async {
  final authService = AuthService();
  return await authService.determineInitialScreen();
}

/// Global navigator key for navigation outside widget context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Root widget for the Taxi App.
/// Sets up providers, theming, and navigation.
class MyApp extends StatelessWidget {
  final Widget initialScreen;
  final SharedPreferences prefs;
  final bool seenOnboarding;

  const MyApp({super.key, required this.initialScreen, required this.prefs, required this.seenOnboarding});

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
              create: (_) => AuthViewModel(
                AuthRepository(
                  FirebaseDataSource(),
                ),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => RutaConductorViewModel(),
            ),
            ChangeNotifierProvider(
              create: (_) => Rutaclienteviewmodel(),
            ),
            
            // Add more ViewModels here as needed
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Taxi Ya',
            theme: AppTheme.lightTheme,
            navigatorKey: navigatorKey,
            home: SplashScreen(
              nextScreen: seenOnboarding
                  ? initialScreen
                  : LoginScreen(onFinish: () {
                      // Mark onboarding as seen and navigate
                      prefs.setBool('seenOnboarding', true);
                      navigatorKey.currentState?.pushReplacement(
                        MaterialPageRoute(builder: (_) => initialScreen),
                      );
                    }),
            ),
          ),
        );
      },
    );
  }
}
