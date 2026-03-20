import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:taxi_app/core/services/firebase_service.dart';

Future<void> initializeTrackingNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'tracking_channel', // id
    'Tracking en segundo plano', // name
    description: 'Notificación para el tracking en segundo plano',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initializeLocationNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_channel', // id
    'Ubicación en segundo plano', // name
    description: 'Notificación para servicios de ubicación en segundo plano',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

/// Servicio centralizado para tracking GPS con las siguientes responsabilidades:
/// - Escuchar GPS en tiempo real
/// - Enviar ubicación automáticamente a Firebase
/// - Detener tracking y liberar recursos
class TrackingService {
  final FirebaseService _firebaseService;

  static const _loggerName = 'TrackingService';

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  Position? _lastSentPosition;
  bool _isTracking = false;

  DateTime? _lastSentTime;

  TrackingService({FirebaseService? firebaseService})
    : _firebaseService = firebaseService ?? FirebaseService();

  /// Indica si el tracking está activo.
  bool get isTracking => _isTracking;

  /// Última posición conocida.
  Position? get lastPosition => _lastPosition;

  // ============================================================================
  // ESCUCHAR GPS
  // ============================================================================
  /// Inicia el tracking de ubicación GPS en tiempo real.
  ///
  /// [onLocationUpdate] - Callback opcional que se ejecuta cada vez que hay una nueva ubicación.
  /// [distanceFilter] - Distancia mínima en metros para enviar actualización (default: 15m).
  /// [timeInterval] - Intervalo mínimo en segundos para actualizaciones (default: 10s).
  ///
  /// Retorna `true` si el tracking se inició correctamente, `false` si ya estaba activo.
  Future<bool> iniciarEscuchaGPS({
    Function(Position)? onLocationUpdate,
    double distanceFilter = 15.0,
    int timeInterval = 10,
  }) async {
    if (_isTracking) {
      developer.log(
        '⚠️ TrackingService: El tracking ya está activo.',
        name: _loggerName,
        level: 900,
      );
      return false;
    }

    // ✔ VERIFICAR SI EL GPS ESTA ACTIVADO
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      throw Exception("Activa el GPS para continuar");
    }

    // Verificar permisos de ubicación
    final hasPermission = await PermissionsHelper.requestLocationPermission();
    if (!hasPermission) {
      throw Exception('No se tienen permisos de ubicación');
    }

    // Configuración de precisión para tracking en tiempo real
    // Preferir configuración con servicio en primer plano en Android para mantener tracking si la app pasa a background (ej: al abrir Google Maps externo).
    final locationSettings =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilter.toInt(),
            intervalDuration: Duration(seconds: timeInterval),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Taxi App - Tracking activo',
              notificationText: 'Compartiendo tu ubicación en tiempo real.',
              enableWakeLock: true,
              // notificationIcon eliminado para usar el predeterminado del sistema
            ),
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilter.toInt(),
          );

    try {
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              // FILTRO DE PRECISIÓN GPS
              if (position.accuracy > 30) {
                developer.log(
                  "⚠️ Ubicación descartada por baja precisión (${position.accuracy}m)",
                  name: _loggerName,
                );
                return;
              }

              // NUEVO: FILTRO DE SALTO GPS
              if (_lastPosition != null) {
                final distancia = Geolocator.distanceBetween(
                  _lastPosition!.latitude,
                  _lastPosition!.longitude,
                  position.latitude,
                  position.longitude,
                );

                if (distancia > 200) {
                  developer.log(
                    "⚠️ Salto GPS descartado: $distancia metros",
                    name: _loggerName,
                  );
                  return;
                }
              }

              _lastPosition = position;

              onLocationUpdate?.call(position);
            },
            onError: (error) {
              developer.log(
                '❌ Error en tracking GPS: $error',
                name: _loggerName,
                level: 1000,
              );
            },
          );

      _isTracking = true;
      developer.log(
        '✅ TrackingService: Escucha GPS iniciada.',
        name: _loggerName,
        level: 800,
      );
      return true;
    } catch (e) {
      developer.log(
        '❌ Error al iniciar tracking GPS: $e',
        name: _loggerName,
        level: 1000,
      );
      return false;
    }
  }

  /// Obtiene la ubicación actual una sola vez (sin streaming).
  ///
  /// Útil para obtener la posición inicial sin iniciar el tracking continuo.
  Future<Position?> obtenerUbicacionActual() async {
    try {
      final hasPermission = await PermissionsHelper.requestLocationPermission();
      if (!hasPermission) {
        throw Exception('No se tienen permisos de ubicación');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      _lastPosition = position;
      return position;
    } catch (e) {
      developer.log(
        '❌ Error al obtener ubicación actual: $e',
        name: _loggerName,
        level: 1000,
      );
      return null;
    }
  }

  // ============================================================================
  // ENVIAR UBICACIÓN
  // ============================================================================
  /// Inicia tracking GPS y envía automáticamente la ubicación a Firebase.
  ///
  /// [userId] - ID del usuario (conductor o cliente).
  /// [userType] - Tipo de usuario: 'conductor' o 'cliente'.
  /// [solicitudId] - ID de la solicitud activa (opcional, para actualizar ubicación en solicitud).
  /// [distanceFilter] - Distancia mínima para enviar actualización (default: 15m).
  /// [timeInterval] - Intervalo mínimo de actualización (default: 10s).
  Future<bool> iniciarTrackingConEnvio({
    required String userId,
    required String userType,
    String? solicitudId,
    double distanceFilter = 15.0,
    int timeInterval = 10,
  }) async {
    // Send one immediate point so background mode persists location quickly
    // even when the user is not moving.
    final initial = await obtenerUbicacionActual();
    if (initial != null) {
      try {
        await enviarUbicacion(
          userId: userId,
          userType: userType,
          position: initial,
          solicitudId: solicitudId,
        );
        _lastSentPosition = initial;
        _lastSentTime = DateTime.now();
      } catch (e) {
        developer.log(
          "❌ Error enviando ubicación inicial: $e",
          name: _loggerName,
        );
      }
    }

    return await iniciarEscuchaGPS(
      distanceFilter: distanceFilter,
      timeInterval: timeInterval,
      onLocationUpdate: (position) async {
        // NUEVO: evitar enviar si no se movió realmente
        if (_lastSentPosition != null) {
          final distancia = Geolocator.distanceBetween(
            _lastSentPosition!.latitude,
            _lastSentPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          if (distancia < 5) {
            return;
          }
        }

        // CONTROL DE FRECUENCIA
        if (_lastSentTime != null &&
            DateTime.now().difference(_lastSentTime!).inSeconds < 5) {
          return;
        }

        try {
          await enviarUbicacion(
            userId: userId,
            userType: userType,
            position: position,
            solicitudId: solicitudId,
          );

          _lastSentPosition = position;
          _lastSentTime = DateTime.now();
        } catch (e) {
          developer.log(
            "❌ Error enviando ubicación (reintentará): $e",
            name: _loggerName,
          );
        }
      },
    );
  }

  /// Envía la ubicación actual a Firebase.
  ///
  /// [userId] - ID del usuario.
  /// [userType] - 'conductor' o 'cliente'.
  /// [position] - Posición a enviar (si es null, usa la última conocida).
  /// [solicitudId] - ID de solicitud activa (opcional).
  Future<void> enviarUbicacion({
    required String userId,
    required String userType,
    Position? position,
    String? solicitudId,
  }) async {
    final ubicacion = position ?? _lastPosition;
    if (ubicacion == null) {
      developer.log(
        '⚠️ No hay ubicación disponible para enviar.',
        name: _loggerName,
        level: 900,
      );
      return;
    }

    final latLng = LatLng(ubicacion.latitude, ubicacion.longitude);

    try {
      if (userType == 'conductor') {
        // Regla de tracking: la ubicación GPS del conductor se persiste solo en
        // la solicitud activa, nunca en el documento de usuario.
        if (solicitudId == null || solicitudId.trim().isEmpty) {
          developer.log(
            '⚠️ solicitudId ausente: se omite persistencia GPS del conductor fuera de solicitudes.',
            name: _loggerName,
            level: 900,
          );
          return;
        }

        await _firebaseService.actualizarUbicacionConductorEnSolicitud(
          solicitudId: solicitudId,
          position: latLng,
        );
      } else if (userType == 'cliente') {
        await _firebaseService.guardarUbicacionCliente(
          clienteId: userId,
          position: latLng,
        );
      }

      developer.log(
        '📍 Ubicación enviada: ${latLng.latitude}, ${latLng.longitude}',
        name: _loggerName,
        level: 800,
      );
    } catch (e) {
      developer.log(
        '❌ Error al enviar ubicación: $e',
        name: _loggerName,
        level: 1000,
      );
    }
  }

  // ============================================================================
  // DETENER TRACKING
  // ============================================================================
  /// Detiene el tracking GPS y libera recursos.
  ///
  /// Cancela la suscripción al stream de posiciones y marca el tracking como inactivo.
  Future<void> detenerTracking() async {
    if (!_isTracking) {
      developer.log(
        '⚠️ TrackingService: El tracking ya está detenido.',
        name: _loggerName,
        level: 900,
      );
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _lastSentPosition = null;
    _lastSentTime = null;

    developer.log(
      '🛑 TrackingService: Tracking detenido.',
      name: _loggerName,
      level: 800,
    );
  }

  /// Limpia completamente el servicio, deteniendo tracking y eliminando referencias.
  ///
  /// Debe llamarse cuando el servicio ya no se va a usar (ej: dispose de un ViewModel).
  Future<void> dispose() async {
    await detenerTracking();
    _lastPosition = null;
    developer.log(
      ' TrackingService: Recursos liberados.',
      name: _loggerName,
      level: 800,
    );
  }

  // ============================================================================
  // UTILIDADES
  // ============================================================================
  /// Calcula la distancia en metros entre dos posiciones.
  double calcularDistancia(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  /// Verifica si el usuario se ha movido significativamente desde una posición anterior.
  ///
  /// [previousPosition] - Posición anterior.
  /// [umbral] - Distancia mínima en metros para considerar movimiento (default: 10m).
  bool haMovidoSignificativamente({
    required LatLng previousPosition,
    double umbral = 10.0,
  }) {
    if (_lastPosition == null) return false;

    final currentLatLng = LatLng(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
    );
    final distancia = calcularDistancia(previousPosition, currentLatLng);

    return distancia >= umbral;
  }
}
