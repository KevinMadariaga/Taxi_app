import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/permisos_helper.dart';


class UbicacionService {
  UbicacionService._internal();
  static final UbicacionService _instance = UbicacionService._internal();
  factory UbicacionService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<Position>? _positionStream;
  final StreamController<LatLng> _locationController = StreamController<LatLng>.broadcast();

  /// Última ubicación conocida (cacheada)
  LatLng? lastKnownLocation;

  /// Stream broadcast para suscribirse a actualizaciones de ubicación
  Stream<LatLng> get onLocationChanged => _locationController.stream;

  /// Solicita y devuelve la ubicación actual una sola vez.
  Future<LatLng?> obtenerUbicacionActual() async {
     // Verificar y solicitar permisos usando PermissionsHelper
    final hasPermission = await PermissionsHelper.requestLocationPermission();
    if (!hasPermission) return null;

    try {
      final Position posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final latlng = LatLng(posicion.latitude, posicion.longitude);
      lastKnownLocation = latlng;
      // notificar a los listeners si hay alguno
      if (!_locationController.isClosed) _locationController.add(latlng);
      return latlng;
    } catch (_) {
      return null;
    }
  }

  /// Comienza a escuchar cambios de ubicación y publica en `onLocationChanged`.
  /// Si ya está escuchando, no reinicia la suscripción.
  void startListening({int distanceFilter = 10, LocationAccuracy accuracy = LocationAccuracy.high}) {
    if (_positionStream != null) return;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    ).listen((pos) {
      final latlng = LatLng(pos.latitude, pos.longitude);
      lastKnownLocation = latlng;
      if (!_locationController.isClosed) _locationController.add(latlng);
    });
  }

  /// Permite escuchar con un callback específico sin suscribirse al stream.
  void escucharUbicacion(void Function(Position) onUbicacionCambio) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(onUbicacionCambio);
  }

  /// Detiene la escucha activa (no cierra el stream broadcast interno).
  void stopListening() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  /// Cierra recursos internos (llamar al destruir la app o provider si es necesario)
  Future<void> dispose() async {
    await _positionStream?.cancel();
    _positionStream = null;
    if (!_locationController.isClosed) await _locationController.close();
  }

  /// Obtiene la ubicación actual y opcionalmente la pasa al callback `onResult`.
  /// El callback puede guardar la ubicación en Firestore, SharedPreferences, etc.
  Future<LatLng?> obtenerYEnviarUbicacion({void Function(LatLng)? onResult}) async {
    final latlng = await obtenerUbicacionActual();
    if (latlng != null && onResult != null) {
      try {
        onResult(latlng);
      } catch (_) {}
    }
    return latlng;
  }

  /// Inicia la escucha (si no está iniciada) y suscribe un callback al stream
  /// broadcast; devuelve la suscripción para que el llamador la cancele cuando quiera.
  StreamSubscription<LatLng> listenWithCallback(void Function(LatLng) onData, {int distanceFilter = 10, LocationAccuracy accuracy = LocationAccuracy.high}) {
    startListening(distanceFilter: distanceFilter, accuracy: accuracy);
    return onLocationChanged.listen(onData);
  }
}
