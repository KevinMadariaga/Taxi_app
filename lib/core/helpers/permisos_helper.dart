import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper centralizado para gestión de permisos de:
/// - Ubicación (primer plano y segundo plano)
/// - Notificaciones
class PermissionsHelper {
  static bool _isPermissionRequestInProgress = false;
  static final List<Future<void> Function()> _permissionQueue = [];

  static Future<T> _runExclusive<T>(Future<T> Function() callback) {
    final completer = Completer<T>();

    Future<void> execute() async {
      try {
        final result = await callback();
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      } finally {
        _isPermissionRequestInProgress = false;
        if (_permissionQueue.isNotEmpty) {
          final next = _permissionQueue.removeAt(0);
          _isPermissionRequestInProgress = true;
          next();
        }
      }
    }

    if (_isPermissionRequestInProgress) {
      _permissionQueue.add(execute);
    } else {
      _isPermissionRequestInProgress = true;
      execute();
    }

    return completer.future;
  }

  // ============================================================================
  // UBICACIÓN - Verificación
  // ============================================================================

  /// Verifica si el servicio de ubicación está activo en el dispositivo.
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Verifica el estado actual del permiso de ubicación (primer plano).
  static Future<LocationPermission> checkLocationPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Verifica si el permiso de ubicación está concedido (primer plano o siempre).
  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Verifica si tiene permiso de ubicación en segundo plano (always).
  static Future<bool> hasBackgroundLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  // ============================================================================
  // UBICACIÓN - Solicitud
  // ============================================================================

  /// Solicita permiso de ubicación en primer plano.
  ///
  /// Retorna `true` si el permiso fue concedido.
  /// Si es denegado permanentemente, abre la configuración de la app.
  static Future<bool> requestLocationPermission() async {
    return await _runExclusive(() async {
      // Verificar si el servicio está habilitado
      if (!await isLocationServiceEnabled()) {
        debugPrint('⚠️ Servicio de ubicación desactivado');
        return false;
      }

      var permission = await Geolocator.checkPermission();

      // Si ya está denegado, pedir permiso
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Si fue denegado permanentemente, abrir configuración
      if (permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Permiso de ubicación denegado permanentemente');
        await openAppSettings();
        return false;
      }

      final granted =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (granted) {
        debugPrint('✅ Permiso de ubicación concedido');
      } else {
        debugPrint('❌ Permiso de ubicación denegado');
      }

      return granted;
    });
  }

  /// Solicita permiso de ubicación en segundo plano (solo para conductores).
  ///
  /// Retorna `true` si el permiso fue concedido.
  static Future<bool> requestBackgroundLocationPermission() async {
    return await _runExclusive(() async {
      // Si Geolocator ya confirma "always", no re-solicitar — en iOS llamar
      // Permission.locationAlways.request() cuando ya está concedido devuelve
      // denied porque el sistema no muestra el prompt de nuevo.
      final current = await Geolocator.checkPermission();
      if (current == LocationPermission.always) {
        debugPrint('✅ Ubicación en segundo plano ya concedida (geolocator)');
        return true;
      }

      // iOS: permission_handler gestiona su propio estado de permisos,
      // independiente de geolocator. Si geolocator ya obtuvo whileInUse
      // pero permission_handler aún no lo sabe, el request de locationAlways
      // falla. Primero garantizamos que permission_handler tenga whileInUse.
      if (Platform.isIOS) {
        final whenInUse = await Permission.locationWhenInUse.status;
        if (!whenInUse.isGranted) {
          final result = await Permission.locationWhenInUse.request();
          if (!result.isGranted) {
            debugPrint(
              '❌ [iOS] locationWhenInUse no concedido via permission_handler',
            );
            return false;
          }
        }
      }

      final backgroundPermission = await Permission.locationAlways.request();

      if (backgroundPermission.isGranted) {
        debugPrint('✅ Ubicación en segundo plano permitida (conductor)');
        return true;
      } else {
        debugPrint(
          '❌ Ubicación en segundo plano no permitida — estado: $backgroundPermission',
        );
        if (await Permission.locationAlways.isPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      }
    });
  }

  /// Solicita exención de optimización de batería (solo Android, solo
  /// conductores). Sin esto, fabricantes con administración agresiva de
  /// batería (MIUI/Xiaomi, EMUI/Huawei, ColorOS/Oppo, etc.) pueden congelar
  /// las actualizaciones de ubicación del foreground service en segundo
  /// plano — el tracking se ve "trabado" o directamente no llega al
  /// cliente aunque el código de la app esté corriendo correctamente.
  ///
  /// Es un permiso especial (no aparece en `requestAllPermissions`
  /// results de forma bloqueante): si el usuario lo rechaza, el tracking
  /// sigue funcionando en la mayoría de dispositivos, solo con más riesgo
  /// de cortes en fabricantes agresivos.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return await _runExclusive(() async {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;

      final result = await Permission.ignoreBatteryOptimizations.request();
      if (result.isGranted) {
        debugPrint('✅ Exención de optimización de batería concedida');
      } else {
        debugPrint(
          '⚠️ Exención de optimización de batería no concedida — el '
          'tracking en background puede ser menos confiable en este '
          'dispositivo.',
        );
      }
      return result.isGranted;
    });
  }

  // ============================================================================
  // NOTIFICACIONES
  // ============================================================================

  /// Verifica si el permiso de notificaciones está concedido.
  static Future<bool> hasNotificationPermission() async {
    if (Platform.isIOS) {
      // En iOS, permission_handler puede devolver 'denied' para el estado
      // 'notDetermined'. Verificamos directamente con flutter_local_notifications.
      final plugin = FlutterLocalNotificationsPlugin();
      final iosImpl = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (iosImpl != null) {
        final settings = await iosImpl.checkPermissions();
        return settings?.isEnabled ?? false;
      }
      // Fallback
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Solicita permiso de notificaciones.
  ///
  /// Retorna `true` si el permiso fue concedido.
  static Future<bool> requestNotificationPermission() async {
    return await _runExclusive(() async {
      if (Platform.isIOS) {
        // En iOS, usamos flutter_local_notifications directamente porque
        // es quien interactúa correctamente con UNUserNotificationCenter.
        // permission_handler puede generar conflictos de timing en iOS.
        final plugin = FlutterLocalNotificationsPlugin();
        final iosImpl = plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

        if (iosImpl != null) {
          // Inicializar si aún no está listo
          await plugin.initialize(
            const InitializationSettings(
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          );

          final bool? granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          final isGranted = granted ?? false;
          if (isGranted) {
            debugPrint('✅ Notificaciones permitidas (iOS)');
          } else {
            // Verificar si fue denegado permanentemente para guiar al usuario
            final status = await Permission.notification.status;
            if (status.isPermanentlyDenied) {
              debugPrint(
                '⚠️ Notificaciones denegadas permanentemente. '
                'El usuario debe habilitarlas desde Ajustes → Ride.',
              );
              // No abrir Ajustes automáticamente; hacerlo desde la UI
            } else {
              debugPrint(
                '⚠️ Notificaciones no otorgadas aún en iOS '
                '(el usuario puede habilitarlas desde Ajustes).',
              );
            }
          }
          return isGranted;
        }

        // Fallback: si no hay implementación iOS disponible aún
        debugPrint(
          '⚠️ IOSFlutterLocalNotificationsPlugin no disponible todavía.',
        );
        return false;
      }

      // Android y otras plataformas
      final permission = await Permission.notification.request();

      if (permission.isGranted) {
        debugPrint('✅ Notificaciones permitidas');
        return true;
      } else {
        debugPrint('❌ Notificaciones no permitidas');
        if (await Permission.notification.isPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      }
    });
  }

  // ============================================================================
  // SOLICITUD COMBINADA
  // ============================================================================

  /// Solicita todos los permisos necesarios según el tipo de usuario.
  ///
  /// [isDriver] - Si es conductor, solicita también ubicación en segundo plano.
  ///
  /// Retorna un mapa con el estado de cada permiso solicitado.
  static Future<Map<String, bool>> requestAllPermissions({
    bool isDriver = false,
  }) async {
    final results = <String, bool>{};

    // Notificaciones
    results['notifications'] = await requestNotificationPermission();

    // Ubicación en primer plano
    results['location'] = await requestLocationPermission();

    // Ubicación en segundo plano (solo conductores)
    if (isDriver) {
      results['backgroundLocation'] =
          await requestBackgroundLocationPermission();
      results['ignoreBatteryOptimizations'] =
          await requestIgnoreBatteryOptimizations();
    }

    return results;
  }

  /// Verifica si todos los permisos necesarios están concedidos.
  ///
  /// [isDriver] - Si es conductor, verifica también ubicación en segundo plano.
  static Future<bool> hasAllPermissions({bool isDriver = false}) async {
    final hasNotifications = await hasNotificationPermission();
    final hasLocation = await hasLocationPermission();

    if (!isDriver) {
      return hasNotifications && hasLocation;
    }

    final hasBackground = await hasBackgroundLocationPermission();
    return hasNotifications && hasLocation && hasBackground;
  }

  // ============================================================================
  // UTILIDADES
  // ============================================================================

  /// Abre la configuración de la aplicación para que el usuario
  /// pueda cambiar los permisos manualmente.
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
