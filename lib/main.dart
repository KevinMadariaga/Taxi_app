import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/core/helpers/firebase_helper.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/core/utils/app_dependencies.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_apple_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/send_client_phone_otp_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/verify_client_phone_otp_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/features/client/data/firebaseDB.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/app_auth_adapter.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/models/AuthModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/RutaConductorViewModel.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:taxi_app/core/services/fcm_service.dart';

const SystemUiOverlayStyle _globalSystemOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
);

/// Error benigno conocido de google_maps_flutter_ios: cuando la vista del mapa
/// se destruye/queda offstage mientras corre el sync interno
/// `updateClusterManagers`, lanza un `channel-error` async. No afecta nada;
/// lo filtramos para no ensuciar la consola. Cualquier otro error propaga.
bool _esErrorBenignoMapas(Object error) {
  if (error is! PlatformException) return false;
  final detalle = '${error.code} ${error.message ?? ''}';
  return detalle.contains('updateClusterManagers') ||
      (error.code == 'channel-error' &&
          detalle.contains('google_maps_flutter'));
}

/// Entry point for the Taxi App.
/// Initializes services, handles permissions, and launches the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_globalSystemOverlayStyle);

  // Filtra el channel-error benigno de google_maps_flutter_ios
  // (updateClusterManagers al destruir la vista). Todo lo demás propaga normal.
  final flutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_esErrorBenignoMapas(details.exception)) return;
    flutterOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_esErrorBenignoMapas(error)) return true; // tragado
    return false; // no manejado → comportamiento por defecto
  };

  // Solo lo imprescindible antes del primer frame: Firebase es requerido por
  // los providers (AppAuthAdapter). Todo lo demás (permisos, notificaciones,
  // tracking, FCM) se difiere para que el splash animado aparezca de inmediato
  // y NUNCA quede una pantalla negra/blanca mientras se piden permisos.
  await FirebaseHelper.initializeFirebase();

  if (!kReleaseMode && AppConstants.phoneAuthTestMode) {
    // In non-release environments this avoids Play Integrity/SafetyNet blocks
    // while phone auth is being configured in Firebase Console.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );

    if (kDebugMode) {
      debugPrint(
        'FirebaseAuth test app verification is enabled (non-release).',
      );
    }
  }

  final dependencies = AppDependencies.initialize();
  runApp(MyApp(dependencies: dependencies));

  // Inicialización diferida en segundo plano: no bloquea el primer frame ni
  // el splash. Los permisos se piden con el splash animado ya visible.
  unawaited(_inicializarServiciosDiferidos());
}

/// Inicializa permisos, notificaciones, tracking y FCM después de mostrar la UI.
/// Cada paso va protegido para que un fallo no detenga el resto.
Future<void> _inicializarServiciosDiferidos() async {
  try {
    await PermissionsHelper.requestAllPermissions();
  } catch (_) {}
  try {
    await NotificacionesServicio.instance.init();
  } catch (_) {}
  try {
    await initializeLocationNotificationChannel();
  } catch (_) {}
  try {
    await initializeTrackingNotificationChannel();
  } catch (_) {}
  try {
    await initializeBackgroundService();
  } catch (_) {}
  // FCM al final: en iOS la espera del token APNs puede tardar varios segundos.
  try {
    await FcmService.instance.init();
  } catch (_) {}
}

/// Root widget for the Taxi App.
/// Sets up providers, theming, and navigation.
class MyApp extends StatelessWidget {
  MyApp({super.key, required this.dependencies})
    : _authAdapter = AppAuthAdapter(FirebaseDataSource());

  final AppDependencies dependencies;
  final AppAuthAdapter _authAdapter;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MultiProvider(
          providers: [
            Provider<ClientAuthRepository>.value(value: _authAdapter),

            // Domain usecases provided centrally so consumers can obtain them
            Provider<SignInGoogleClientUseCase>(
              create: (ctx) =>
                  SignInGoogleClientUseCase(ctx.read<ClientAuthRepository>()),
            ),
            Provider<SignInAppleClientUseCase>(
              create: (ctx) =>
                  SignInAppleClientUseCase(ctx.read<ClientAuthRepository>()),
            ),
            Provider<SendClientPhoneOtpUseCase>(
              create: (ctx) =>
                  SendClientPhoneOtpUseCase(ctx.read<ClientAuthRepository>()),
            ),
            Provider<VerifyClientPhoneOtpUseCase>(
              create: (ctx) =>
                  VerifyClientPhoneOtpUseCase(ctx.read<ClientAuthRepository>()),
            ),
            Provider<GetClientUserUseCase>(
              create: (ctx) =>
                  GetClientUserUseCase(ctx.read<ClientAuthRepository>()),
            ),
            Provider<CompleteClientProfileUseCase>(
              create: (ctx) => CompleteClientProfileUseCase(
                ctx.read<ClientAuthRepository>(),
              ),
            ),

            ChangeNotifierProvider(create: (_) => AuthViewModel(_authAdapter)),
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
