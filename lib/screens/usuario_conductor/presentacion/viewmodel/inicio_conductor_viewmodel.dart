import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/data/models/solicitud_id.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:taxi_app/services/ubicacion_servicio.dart';
import 'package:taxi_app/services/notification_service.dart';
import 'dart:async';

class HomeConductorViewModel extends ChangeNotifier {
  final UbicacionService _ubicacionService = UbicacionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();
  final TrackingService _trackingService = TrackingService();

  bool _disposed = false;

  String displayName = 'Conductor';
  String? photoUrl;
  String? nameFromDb;
  String? plate;
  
  String? get vehiclePlate => plate;

  LatLng? currentLocation;

  bool isLoading = true;
  bool loadingLocation = true;
  final List<SolicitudItem> solicitudes = [];
  StreamSubscription<QuerySnapshot>? _sub;

  // UI state for HomeConductor screen
  PreviewSolicitud? selectedPreview;
  bool isMapExpanded = false;

  // Stream to notify UI about newly arrived pending solicitudes
  final StreamController<String> _newSolicitudController = StreamController<String>.broadcast();
  Stream<String> get onNewSolicitud => _newSolicitudController.stream;
  final Set<String> _knownPendingIds = {};

  // Route and marker state for selected solicitud
  final Map<String, List<LatLng>> routePoints = {};
  final Set<Polyline> routePolylines = {};
  final Set<Marker> extraMarkers = {};

  HomeConductorViewModel();

  Future<void> init() async {
    isLoading = true;
    loadingLocation = true;
    _safeNotify();

    await _loadProfile();
    await _requestBackgroundLocationPermission();
    await _loadLocation();
    _subscribeSolicitudes();

    isLoading = false;
    loadingLocation = false;
    _safeNotify();
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        photoUrl = user.photoURL;
        if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
          displayName = user.displayName!.trim();
        } else if (user.email != null && user.email!.contains('@')) {
          final namePart = user.email!.split('@').first;
          if (namePart.isNotEmpty) displayName = '${namePart[0].toUpperCase()}${namePart.substring(1)}';
        }

        final uid = user.uid;
        try {
          final snap = await _firestore.collection('conductor').doc(uid).get();
          if (snap.exists) {
            final data = snap.data();
              nameFromDb = data?['nombre']?.toString();
              plate = data?['placa']?.toString();
              // Preferir la foto almacenada en Firestore si existe
              final fotoFromDb = data?['fotoUrl'] ?? data?['foto'] ?? data?['photoUrl'];
              if (fotoFromDb != null && fotoFromDb.toString().trim().isNotEmpty) {
                photoUrl = fotoFromDb.toString().trim();
              }
            if (nameFromDb != null && nameFromDb!.trim().isNotEmpty) {
              displayName = nameFromDb!.trim();
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadLocation() async {
    loadingLocation = true;
    notifyListeners();
    try {
      // Obtener ubicación con TrackingService
      final position = await _trackingService.obtenerUbicacionActual();
      if (position != null) {
        currentLocation = LatLng(position.latitude, position.longitude);
        
        // Guardar ubicación en Firebase
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          try {
            await _firebaseService.guardarUbicacionConductor(
              conductorId: uid,
              position: currentLocation!,
            );
          } catch (e) {
            debugPrint('Error guardando ubicación del conductor: $e');
          }
        }
      }
    } catch (_) {}
    loadingLocation = false;
    _safeNotify();
  }

  Future<void> _requestBackgroundLocationPermission() async {
    try {
      await PermissionsHelper.requestBackgroundLocationPermission();
    } catch (_) {}
  }

  Future<void> refreshLocation() async {
    await _loadLocation();
  }

  // ===== UI state helpers =====

  void selectPreview(PreviewSolicitud preview) {
    selectedPreview = preview;
    isMapExpanded = false;
    _safeNotify();
  }

  void clearPreviewAndRoutes() {
    selectedPreview = null;
    isMapExpanded = false;
    routePoints.clear();
    routePolylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
    extraMarkers.removeWhere((m) => m.markerId.value == 'driver');
    _safeNotify();
  }

  void setMapExpanded(bool value) {
    if (isMapExpanded == value) return;
    isMapExpanded = value;
    _safeNotify();
  }

  void setRoute(String id, List<LatLng> points) {
    routePoints[id] = points;
    routePolylines.removeWhere((p) => p.polylineId.value == 'route_$id');
    routePolylines.add(
      Polyline(
        polylineId: PolylineId('route_$id'),
        color: AppColores.primary,
        width: 5,
        points: points,
      ),
    );
    _safeNotify();
  }

  void _subscribeSolicitudes() {
    _sub?.cancel();
    _sub = _firestore.collection('solicitudes').snapshots().listen((snap) {
      solicitudes.clear();
      // Detect pending solicitudes and emit notification events for newly arrived ones
      final currentPendingIds = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final st = data['estado'] ?? data['status'];
        if (st == null) continue;
        final stLower = st.toString().toLowerCase();
        if (!(stLower == 'buscando' || stLower == 'pending' || stLower == 'pendiente')) continue;

        // mark as pending for notification comparison
        currentPendingIds.add(doc.id);

        GeoPoint? origen;
        String? origenAddress;
        String? origenTitle;

        // 1) Prefer nested cliente.ubicacion (nuevo esquema)
        final rawCliente = data['cliente'];
        if (rawCliente is Map && rawCliente['ubicacion'] is Map) {
          try {
            final u = rawCliente['ubicacion'];
            final lat = (u['lat'] as num?)?.toDouble();
            final lng = (u['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              origen = GeoPoint(lat, lng);
            }
            origenAddress = (u['address'] ?? u['direccion'])?.toString();
            origenTitle = origenAddress;
          } catch (_) {}
        }

        // 2) Fallbacks antiguos: ubicacion_inicial u origen
        if (origen == null && data['ubicacion_inicial'] is GeoPoint) {
          origen = data['ubicacion_inicial'] as GeoPoint;
        } else if (origen == null && data['origen'] is Map) {
          try {
            final o = data['origen'];
            final lat = (o['lat'] as num?)?.toDouble();
            final lng = (o['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) origen = GeoPoint(lat, lng);
            if (o['address'] != null) {
              origenAddress = o['address']?.toString();
            } else if (o['direccion'] != null) {
              origenAddress = o['direccion']?.toString();
            }
            // Try to capture a human-friendly title for the origin if present
            if (o['title'] != null) {
              origenTitle = o['title']?.toString();
            } else if (o['address'] != null) {
              origenTitle = o['address']?.toString();
            } else if (o['direccion'] != null) {
              origenTitle = o['direccion']?.toString();
            }
          } catch (_) {}
        }
        if (origen == null) continue;

        // cliente may be a nested map {id, nombre} or just an id string
        String? clienteId;
        String? nombreClienteFromData;
        final clienteField = rawCliente;
        if (clienteField is Map) {
          clienteId = (clienteField['id'] ?? clienteField['uid'] ?? clienteField['clienteId'])?.toString();
          nombreClienteFromData = (clienteField['nombre'] ?? clienteField['name'])?.toString();
        }
        clienteId ??= data['clienteId']?.toString() ?? data['cliente']?.toString();
        if (clienteId == null) continue;

        final item = SolicitudItem(
          id: doc.id,
          clienteId: clienteId,
          ubicacionInicial: origen,
          ubicacionDestino: null,
          metodoPago: (data['metodoPago'] ?? data['metodo_pago'] ?? data['metodo'])?.toString(),
        );

        // prefer name from nested cliente map, then common top-level keys
        item.nombreCliente = nombreClienteFromData ?? (data['nombreCliente'] ?? data['nombre_cliente'] ?? data['clienteNombre'] ?? data['nombre'])?.toString();
        if (origenAddress == null && data['origen'] is Map) {
          final o = data['origen'];
          origenAddress = (o['address'] ?? o['direccion'] ?? o['address_text'])?.toString();
        }
        // Prefer explicit origenTitle if available, otherwise use direccion
        item.origenTitle = origenTitle ?? (data['origen'] is Map ? (data['origen']['title'] ?? null)?.toString() : null);
        item.direccion = origenAddress ?? (data['direccion'] ?? data['direccion_recoger'] ?? data['direccion_origen'] ?? data['ubicacion_text'])?.toString();

        if (currentLocation != null) {
          item.distanciaKm = _distanceKm(
            currentLocation!.latitude,
            currentLocation!.longitude,
            origen.latitude,
            origen.longitude,
          );
        }

        solicitudes.add(item);
        _completarDatosSolicitud(item);
      }
      // Compare with known pending ids to find newly arrived pending solicitudes
      try {
        for (final id in currentPendingIds) {
          if (!_knownPendingIds.contains(id)) {
            // emit event for UI to show notification
            try {
              _newSolicitudController.add(id);
            } catch (_) {}
            // also show a local notification
            try {
              NotificationService.instance.showNotification(
                id.hashCode & 0x7fffffff,
                'Solicitud entrante',
                'Cliente necesita servicio',
              );
            } catch (_) {}
          }
        }
        // update known set
        _knownPendingIds
          ..clear()
          ..addAll(currentPendingIds);
      } catch (_) {}
      solicitudes.sort((a, b) => (a.distanciaKm ?? double.maxFinite).compareTo(b.distanciaKm ?? double.maxFinite));
      _safeNotify();
    });
  }

  Future<void> _completarDatosSolicitud(SolicitudItem item) async {
    try {
      if (item.nombreCliente == null) {
        final cli = await _firestore.collection('cliente').doc(item.clienteId).get();
        item.nombreCliente = cli.data()?['nombre']?.toString() ?? 'Cliente';
      }
      if (item.direccion == null) {
        item.direccion = 'Ubicación del cliente';
      }
      _safeNotify();
    } catch (_) {}
  }

  SolicitudItem? get firstSolicitud => solicitudes.isNotEmpty ? solicitudes.first : null;

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);
  /// Centra la cámara del mapa en `currentLocation` si está disponible.
  ///
  /// Pasa el `GoogleMapController` activo y opcionalmente el nivel de zoom.
  Future<void> centerMapOnMarker(GoogleMapController controller, {double zoom = 15.0}) async {
    if (currentLocation == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentLocation!, zoom: zoom),
        ),
      );
    } catch (_) {}
  }

  /// Devuelve un `CameraUpdate` centrado en `currentLocation` o `null` si no hay ubicación.
  CameraUpdate? get cameraUpdateForCurrentLocation {
    if (currentLocation == null) return null;
    return CameraUpdate.newLatLngZoom(currentLocation!, 15.0);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    try { _newSolicitudController.close(); } catch (_) {}
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
