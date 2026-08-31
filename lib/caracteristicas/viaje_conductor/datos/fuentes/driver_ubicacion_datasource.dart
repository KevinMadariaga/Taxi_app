import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/firebase_service.dart';
import 'package:taxi_app/core/services/tracking_service.dart';

/// Envoltorio delgado sobre `TrackingService` (ganador de la consolidación
/// de GPS del conductor — ver plan) para el flujo de viaje activo.
///
/// `TrackingService` ya es la misma clase que corre dentro del isolate de
/// `BackgroundTrackingService`, así que foreground (esta clase, stream en
/// vivo) y background (el isolate, mismo `TrackingService` internamente)
/// terminan siendo literalmente la misma implementación — reemplaza a
/// `DriverLocationService`, que reimplementaba su propio stream de
/// `Geolocator` en paralelo.
class DriverUbicacionDatasource {
  DriverUbicacionDatasource({
    TrackingService? trackingService,
    FirebaseService? firebaseService,
  }) : _tracking = trackingService ?? TrackingService(),
       _firebaseService = firebaseService ?? FirebaseService();

  final TrackingService _tracking;
  final FirebaseService _firebaseService;

  bool get enviando => _tracking.isTracking;
  Position? get ultimaPosicion => _tracking.lastPosition;

  /// Envía un punto inmediato y arranca el stream continuo — mismo
  /// `distanceFilter`/`timeInterval` que ya usaba `DriverLocationService`
  /// (15m / 10s), con el throttle interno de `TrackingService` (5s / 1m)
  /// aplicado antes de cada escritura a Firestore.
  ///
  /// `allowBackground: true` porque este stream es el único que corre
  /// durante todo el viaje: antes se cancelaba al pasar a `paused` para
  /// relevarlo con `BackgroundTrackingService` (que en iOS no hace nada —
  /// ver `background_tracking_service.dart`); ahora el mismo stream sigue
  /// vivo con la pantalla apagada o la app en otra app, gracias a la rama
  /// `AppleSettings` de `TrackingService.iniciarEscuchaGPS`.
  Future<bool> iniciarEnvio({
    required String conductorId,
    required String viajeId,
    void Function(Position)? onLocationUpdate,
  }) {
    return _tracking.iniciarTrackingConEnvio(
      userId: conductorId,
      userType: 'conductor',
      solicitudId: viajeId,
      distanceFilter: 15.0,
      timeInterval: 10,
      allowBackground: true,
      onLocationUpdate: onLocationUpdate,
    );
  }

  /// Resync de un solo punto — usado al volver de background (`resumed`)
  /// para no esperar al próximo tick del stream.
  Future<void> enviarUbicacionActual({
    required String conductorId,
    required String viajeId,
  }) async {
    final posicion = await _tracking.obtenerUbicacionActual();
    if (posicion == null) return;
    await _tracking.enviarUbicacion(
      userId: conductorId,
      userType: 'conductor',
      position: posicion,
      solicitudId: viajeId,
    );
  }

  /// Escribe un punto fijo directo a la solicitud, sin pasar por el stream de
  /// Geolocator — usado por la simulación de recorrido en modo debug (QA sin
  /// mover el dispositivo físicamente).
  Future<void> enviarPuntoSimulado({
    required String viajeId,
    required LatLng position,
  }) {
    return _firebaseService.actualizarUbicacionConductorEnSolicitud(
      solicitudId: viajeId,
      position: position,
    );
  }

  Future<void> detener() => _tracking.detenerTracking();

  Future<void> dispose() => _tracking.dispose();
}
