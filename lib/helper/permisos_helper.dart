import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper centralizado para gestión de permisos de:
/// - Ubicación (primer plano y segundo plano)
/// - Notificaciones
class PermissionsHelper {
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

    final granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    if (granted) {
      debugPrint('✅ Permiso de ubicación concedido');
    } else {
      debugPrint('❌ Permiso de ubicación denegado');
    }

    return granted;
  }

  /// Solicita permiso de ubicación en segundo plano (solo para conductores).
  ///
  /// Retorna `true` si el permiso fue concedido.
  static Future<bool> requestBackgroundLocationPermission() async {
    final backgroundPermission = await Permission.locationAlways.request();

    if (backgroundPermission.isGranted) {
      debugPrint('✅ Ubicación en segundo plano permitida (conductor)');
      return true;
    } else {
      debugPrint('❌ Ubicación en segundo plano no permitida');

      if (await Permission.locationAlways.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }
  }

  // ============================================================================
  // NOTIFICACIONES
  // ============================================================================

  /// Verifica si el permiso de notificaciones está concedido.
  static Future<bool> hasNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Solicita permiso de notificaciones.
  ///
  /// Retorna `true` si el permiso fue concedido.
  static Future<bool> requestNotificationPermission() async {
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
