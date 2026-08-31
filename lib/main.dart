import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:taxi_app/core/helpers/firebase_helper.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_apple_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/presentation/widgets/app_update_gate.dart';
import 'package:taxi_app/features/client/data/firebaseDB.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/app_auth_adapter.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/presentation/viewmodels/auth_view_model.dart';
import 'package:taxi_app/core/services/background_tracking_service.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/app_navigator.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/vistas/chat_screen.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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

/// Maneja el tap en notificaciones locales. Payload:
///   'admin_hub:N'       → AdminHubScreen con pestaña N
///   'admin_conductores' → pop al root (AdminHomeScreen lista de conductores)
///   'soporte_chat'      → SoporteChatScreen (usuario)
///   'viaje_chat:`viajeId`:`currentUserId`:`otherPartyLabel`' → ChatScreen
///     del viaje (ver `ChatController._showMessageNotification`)
void _manejarTapNotificacion(String? payload) {
  if (payload == null) return;
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;

  if (payload.startsWith('admin_hub:')) {
    final tab = int.tryParse(payload.split(':').last) ?? 0;
    nav.push(
      MaterialPageRoute(builder: (_) => AdminHubScreen(initialTab: tab)),
    );
  } else if (payload == 'admin_conductores') {
    // Lleva al admin a su pantalla principal (lista de conductores).
    nav.popUntil((route) => route.isFirst);
  } else if (payload == 'soporte_chat') {
    nav.push(MaterialPageRoute(builder: (_) => const SoporteChatScreen()));
  } else if (payload.startsWith('viaje_chat:')) {
    final partes = payload.split(':');
    if (partes.length < 4) return;
    final viajeId = partes[1];
    final currentUserId = partes[2];
    final otherPartyLabel = partes[3];
    nav.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viajeId: viajeId,
          currentUserId: currentUserId,
          otherPartyLabel: otherPartyLabel,
        ),
      ),
    );
  }
}

/// Entry point for the Taxi App.
/// Instala los handlers globales de error. Debe llamarse **después** de
/// `FirebaseHelper.initializeFirebase()`, que asigna su propio
/// `FlutterError.onError` y pisaría cualquier handler anterior.
void _instalarManejadoresDeError() {
  // Encadena sobre el handler que dejó firebase_helper
  // (`recordFlutterError`) en vez de reemplazarlo, filtrando el channel-error
  // benigno de google_maps_flutter_ios.
  final anterior = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_esErrorBenignoMapas(details.exception)) return;
    anterior?.call(details);
  };

  // Antes devolvía `false` para todo lo no-benigno ("no manejado"), así que
  // los errores async sin capturar solo se imprimían por consola y NUNCA
  // llegaban a Crashlytics — clases enteras de crashes de producción eran
  // invisibles.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_esErrorBenignoMapas(error)) return true; // tragado a propósito
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Pantalla mínima cuando Firebase no pudo inicializar. Sin esto la app
/// quedaba en blanco sin explicación ni salida.
class _ErrorArranqueApp extends StatelessWidget {
  const _ErrorArranqueApp({required this.detalle});

  final String detalle;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo iniciar la aplicación',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Revisa tu conexión a internet y vuelve a abrir la app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    detalle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vacía la bandeja de notificaciones cada vez que la app vuelve a primer
/// plano.
///
/// Las notificaciones locales usan un id fijo por tipo (chat=1, viaje=2,
/// sistema=3), así que se reemplazan entre ellas y no se acumulan. Las que sí
/// se apilaban eran las push que muestra el SISTEMA con la app en segundo plano
/// o cerrada: el SDK de FCM les asigna un id propio cada vez, y quedaban
/// acumuladas en la barra ("llegó tu conductor", mensajes de chat, cambios de
/// estado) mucho después de que el viaje terminara.
///
/// Si el usuario está en la app, ya está viendo el estado real: la bandeja no
/// aporta nada. `cancelAll()` limpia también las de FCM, porque en Android el
/// plugin termina llamando a `NotificationManagerCompat.cancelAll()`, que borra
/// todas las notificaciones de la aplicación.
class _LimpiadorDeBandeja extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    NotificacionesServicio.instance.cancelAll().catchError((
      Object e,
      StackTrace st,
    ) {
      ErrorReporter.report(e, st, reason: 'main: limpiar bandeja al reanudar');
    });
  }
}

/// Initializes services, handles permissions, and launches the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_globalSystemOverlayStyle);

  // Los handlers de error se instalan DESPUÉS de `initializeFirebase()`
  // (ver `_instalarManejadoresDeError` más abajo): ese método asigna su propio
  // `FlutterError.onError`, así que cualquier handler puesto acá arriba se
  // perdería silenciosamente.

  // Fuerza hybrid composition (TextureLayer) en el GoogleMap de Android en vez
  // del SurfaceView por defecto. El SurfaceView pierde su superficie nativa
  // cuando el sistema recrea la Activity tras estar mucho tiempo en segundo
  // plano, dejando la pantalla en negro hasta forzar cierre. Debe fijarse
  // antes de montar cualquier GoogleMap.
  final mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }

  // En Android, sin esto la app queda fija a 60Hz aunque el equipo tenga
  // pantalla de 90/120Hz (a diferencia de iOS, que negocia ProMotion solo).
  // Es un ajuste distinto e independiente del `useAndroidViewSurface` de
  // arriba: uno resuelve qué tan seguido se puede refrescar el mapa, este
  // resuelve a cuántos Hz refresca la pantalla en general. `flutter_displaymode`
  // no tiene implementación iOS — se guarda detrás de `Platform.isAndroid`.
  // Best-effort: si el equipo no soporta modos alternos, no debe bloquear el
  // arranque.
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'main');
    }
  }

  // Solo lo imprescindible antes del primer frame: Firebase es requerido por
  // los providers (AppAuthAdapter). Todo lo demás (permisos, notificaciones,
  // tracking, FCM) se difiere para que el splash animado aparezca de inmediato
  // y NUNCA quede una pantalla negra/blanca mientras se piden permisos.
  // Si Firebase no arranca, `initializeFirebase` lanza. Sin este guard la
  // excepción salía de `main()` y `runApp()` nunca corría: pantalla en blanco
  // permanente, sin mensaje ni forma de reintentar.
  try {
    await FirebaseHelper.initializeFirebase();
  } catch (e) {
    runApp(_ErrorArranqueApp(detalle: e.toString()));
    return;
  }

  _instalarManejadoresDeError();

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

  WidgetsBinding.instance.addObserver(_LimpiadorDeBandeja());

  runApp(MyApp());

  // Inicialización diferida en segundo plano: no bloquea el primer frame ni
  // el splash. Los permisos se piden con el splash animado ya visible.
  unawaited(_inicializarServiciosDiferidos());
}

/// Inicializa permisos, notificaciones, tracking y FCM después de mostrar la UI.
/// Cada paso va protegido para que un fallo no detenga el resto.
Future<void> _inicializarServiciosDiferidos() async {
  try {
    await PermissionsHelper.requestAllPermissions();
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
  try {
    await NotificacionesServicio.instance.init();
    NotificacionesServicio.onNotificationTap = _manejarTapNotificacion;
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
  try {
    await initializeLocationNotificationChannel();
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
  try {
    await initializeTrackingNotificationChannel();
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
  try {
    await initializeBackgroundService();
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
  // FCM al final: en iOS la espera del token APNs puede tardar varios segundos.
  try {
    await FcmService.instance.init();
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'main');
  }
}

/// Root widget for the Taxi App.
/// Sets up providers, theming, and navigation.
class MyApp extends StatelessWidget {
  MyApp({super.key}) : _authAdapter = AppAuthAdapter(FirebaseDataSource());

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
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: AppConstants.appTitle,
            theme: AppThemeConfig.lightTheme,
            navigatorKey: appNavigatorKey,
            initialRoute: AppRoutes.splash,
            onGenerateRoute: AppRoutes.onGenerateRoute,
            builder: (context, child) {
              return AppUpdateGate(
                navigatorKey: appNavigatorKey,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: _globalSystemOverlayStyle,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
