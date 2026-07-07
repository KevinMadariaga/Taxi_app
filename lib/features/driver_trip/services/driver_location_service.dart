import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';

import 'driver_trip_firestore_service.dart';

class DriverLocationService {
  DriverLocationService({DriverTripFirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? DriverTripFirestoreService();

  final DriverTripFirestoreService _firestoreService;

  Stream<Position>? _positionStream;
  StreamSubscription<Position>? _syncSub;
  Stream<Position> get stream => _positionStream ?? const Stream.empty();

  Position? _lastAcceptedPosition;
  DateTime? _lastSentTime;
  // Mismo throttle que TrackingService (flujo legacy): sin esto, cada jitter
  // de GPS >1m dispara una escritura a Firestore y un rebuild del mapa del
  // cliente, congelando la UI en gama baja durante el viaje activo.
  static const Duration _minInterval = Duration(seconds: 5);

  Future<void> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location service disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
  }

  Future<Position> getCurrent() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> startRealtimeSync({required String tripId}) async {
    await ensurePermission();

    // Android: background tracking is handled separately by
    // background_tracking_service (foreground service + isolate).
    // iOS: flutter_background_service cannot keep running reliably once the
    // app is backgrounded/locked, so on iOS this same stream (native
    // CoreLocation background delivery) is what keeps sending the driver's
    // position — requires AppleSettings.allowBackgroundLocationUpdates (true
    // by default) + "Always" location permission + UIBackgroundModes:
    // "location" in Info.plist (already configured).
    _positionStream = Geolocator.getPositionStream(
      locationSettings: Platform.isIOS
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
              pauseLocationUpdatesAutomatically: false,
              showBackgroundLocationIndicator: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            ),
    );

    _syncSub?.cancel();
    _lastAcceptedPosition = null;
    _lastSentTime = null;
    _syncSub = _positionStream!.listen((pos) {
      // Descarta saltos de GPS poco realistas (glitch del sensor), igual que
      // TrackingService (flujo legacy), para que el marcador del cliente no
      // reciba un punto erróneo y haga un salto visual brusco.
      final last = _lastAcceptedPosition;
      if (last != null) {
        final distancia = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (distancia > 200) return;
      }

      final lastSent = _lastSentTime;
      if (lastSent != null && DateTime.now().difference(lastSent) < _minInterval) {
        return;
      }

      _lastAcceptedPosition = pos;
      _lastSentTime = DateTime.now();

      _firestoreService.updateDriverLocation(
        tripId: tripId,
        position: LatLng(pos.latitude, pos.longitude),
      );
    });
  }

  Future<void> syncOneShotToTrip({required String tripId}) async {
    final pos = await getCurrent();
    await _firestoreService.updateDriverLocation(
      tripId: tripId,
      position: LatLng(pos.latitude, pos.longitude),
    );
  }

  String? get currentDriverUid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> stopRealtimeSync() async {
    await _syncSub?.cancel();
    _syncSub = null;
    _positionStream = null;
    _lastAcceptedPosition = null;
    _lastSentTime = null;
  }
}
