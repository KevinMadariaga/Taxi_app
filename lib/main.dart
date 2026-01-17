import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/firebase_helper.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/screens/splash_screen.dart';
import 'package:taxi_app/screens/login_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/data/autenticacion.dart';
import 'package:taxi_app/screens/usuario_cliente/data/firebaseDB.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/autenticacion_viewmodel.dart';
import 'package:taxi_app/services/auth_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/theme/app_theme.dart';
 
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Manejo de errores global en Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Puedes enviar los errores a Crashlytics aquí si lo deseas
  };

  await FirebaseHelper.initializeFirebase();
  await PermissionsHelper.requestAllPermissions();
  
  // Inicializar notificaciones usando el servicio singleton
  await NotificacionesServicio.instance.init();

  // Crear instancia del servicio de autenticación y redirección
  // AuthService ya no necesita el plugin de notificaciones como parámetro
  final authService = AuthService();

  // Determinar la pantalla inicial según el estado de sesión
  final initialScreen = await authService.determineInitialScreen();

  // Revisar si el onboarding ya se mostró
  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seenOnboarding') ?? false;

  runApp(MyApp(initialScreen: initialScreen, prefs: prefs, seenOnboarding: seenOnboarding));
}

// (Inicialización de Firebase movida a `lib/helpers/firebase_helper.dart`)

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

            // 👉 Aquí puedes agregar más ViewModels
            // ChangeNotifierProvider(create: (_) => TripViewModel(...)),
            // ChangeNotifierProvider(create: (_) => MapViewModel(...)),
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
                      // Guardar que ya se mostró el onboarding y navegar usando navigatorKey
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
