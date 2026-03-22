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

    // In this foreground screen we avoid foreground-service location mode.
    // Background tracking is handled separately by background_tracking_service.
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    );

    _syncSub?.cancel();
    _syncSub = _positionStream!.listen((pos) {
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
  }
}
