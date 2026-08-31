import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:taxi_app/firebase_options.dart';

import 'tracking_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

// SIN ARRANCADORES a propósito. Este servicio (basado en
// `flutter_background_service`) relevaba al stream de GPS en primer plano
// cuando `ViajeConductorViewModel` pasaba a `paused` — y ESE relevo era el
// bug: en iOS `onIosBackground` de acá abajo es `return true;`, no manda
// ubicación, así que cancelar el stream principal en el momento del relevo
// dejaba a nadie mandando ubicación mientras el conductor tenía la pantalla
// apagada. Ver `onAppPausedOrInactive`/`onAppResumed` en
// `viaje_conductor_viewmodel.dart`: ahora el stream de
// `TrackingService.iniciarEscuchaGPS` (con `allowBackground: true` y, en
// iOS, `AppleSettings.allowBackgroundLocationUpdates`) corre sin
// interrupción durante todo el viaje y este servicio nunca se arranca.
//
// `startBackgroundTrackingService`/`initializeBackgroundService` quedan
// definidos pero sin llamadores — no se borraron porque `stopBackground
// TrackingService` sigue siendo una red de seguridad real: si un usuario
// actualiza la app con un viaje en curso desde una versión anterior que sí
// dejó este servicio corriendo, algo tiene que poder apagarlo. Ver los
// callers de `stopBackgroundTrackingService` (`dispose()` de este
// ViewModel, `resumen_viaje_view.dart`, `auth_service.dart`,
// `InicioConductorViewModel.dart`).

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'tracking_channel',
      initialNotificationTitle: 'Ride',
      initialNotificationContent: '',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

/// Inicia el servicio solo si no está corriendo
Future<void> startBackgroundTrackingService() async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
    developer.log('✅ Servicio de tracking en segundo plano iniciado');
  } else {
    developer.log('ℹ️ Servicio de tracking ya estaba corriendo');
  }
}

/// Detiene el servicio de tracking en segundo plano (si está corriendo).
/// Útil al salir de las pantallas de viaje (ej. resumen) para no gastar batería.
Future<void> stopBackgroundTrackingService() async {
  try {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
      developer.log('🛑 Servicio de tracking en segundo plano detenido');
    }
  } catch (e, st) {
    developer.log('❌ Error al detener servicio de tracking: $e');
    ErrorReporter.report(
      e,
      st,
      reason:
          'BackgroundTrackingService: fallo al detener el servicio de tracking en segundo plano',
    );
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  final tracking = TrackingService();

  developer.log("🚀 Background tracking iniciado");

  service.on("startTracking").listen((event) async {
    final userId = event?["userId"]?.toString();
    final userType = event?["userType"]?.toString();
    final solicitudId = event?["solicitudId"]?.toString();

    if (userId == null || userId.isEmpty) return;
    if (userType == null || userType.isEmpty) return;

    if (service is AndroidServiceInstance) {
      try {
        await service.setForegroundNotificationInfo(
          title: 'Ride',
          content: userType == 'conductor'
              ? 'Recolectando ubicación en segundo plano'
              : '',
        );
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'background_tracking_service');
      }
    }

    await tracking.iniciarTrackingConEnvio(
      userId: userId,
      userType: userType,
      solicitudId: solicitudId,

      // Background isolate: assume permissions were already granted by foreground.
      // Avoid triggering permission_handler calls from the background isolate.
      // This prevents MissingPluginException in the background isolate.
      // The TrackingService will skip interactive permission requests when this flag is true.
      // Note: Ensure the app requested permissions in foreground before starting background tracking.
      //
      // See permisos_helper.requestAllPermissions usage in UI flow.
      //
      skipPermissionRequest: true,
    );
  });

  service.on("stop").listen((event) {
    tracking.detenerTracking();

    service.stopSelf();
  });
}
