import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:taxi_app/firebase_options.dart';


import 'tracking_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'tracking_channel',
      initialNotificationTitle: 'Taxi App',
      initialNotificationContent: 'Tracking activo',
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
    await service.setForegroundNotificationInfo(
      title: 'Taxi Ya',
      content: 'Recolectando ubicación en segundo plano',
      // El sistema usará el ícono por defecto del app (mipmap/ic_launcher). El plugin no permite especificar ícono personalizado desde Dart.
    );
  }

  final tracking = TrackingService();

  developer.log("🚀 Background tracking iniciado");

  service.on("startTracking").listen((event) async {

    final userId = event?["userId"]?.toString();
    final userType = event?["userType"]?.toString();
    final solicitudId = event?["solicitudId"]?.toString();

    if (userId == null || userId.isEmpty) return;
    if (userType == null || userType.isEmpty) return;

    await tracking.iniciarTrackingConEnvio(
      userId: userId,
      userType: userType,
      solicitudId: solicitudId,
    );

  });

  service.on("stop").listen((event) {

    tracking.detenerTracking();

    service.stopSelf();

  });
}