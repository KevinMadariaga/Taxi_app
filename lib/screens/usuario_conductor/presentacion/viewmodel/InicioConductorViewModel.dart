import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/data/models/solicitud_id.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:taxi_app/core/services/services.dart';

class InicioConductorViewmodel extends ChangeNotifier {
  // Variables de estado y colecciones faltantes
  PreviewSolicitud? selectedPreview;
  bool isMapExpanded = false;
  final Map<String, List<LatLng>> routePoints = {};
  final Set<Polyline> routePolylines = {};
  final Set<Marker> extraMarkers = {};
  bool isConnected = false;
  final Map<String, String> _clientePhotoById = {};
  final Set<String> _clientePhotoLoadedIds = {};
  final Set<String> _knownPendingIds = {};
  final Set<String> _resolvingAddressSolicitudIds = {};
  final StreamController<String> _newSolicitudController =
      StreamController<String>.broadcast();
  Stream<String> get onNewSolicitud => _newSolicitudController.stream;
  StreamSubscription<DocumentSnapshot>? _conductorSub;
  StreamSubscription<QuerySnapshot>? _ratingSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _previewStatusSub;
  StreamSubscription<String?>? _cachedNameSub;
  bool _previewStatusHandled = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TrackingService _trackingService = TrackingService();

  bool _disposed = false;
  bool isTogglingConnection = false;
  double rating = 0.0;
  int totalRatings = 0;
  int totalCompletedTrips = 0;
  double totalServiceValue = 0.0;
  double _ratingFromConductorDoc = 0.0;
  int _totalRatingsFromConductorDoc = 0;

  String displayName = 'Conductor';
  String? photoUrl;

  String? nameFromDb;
  String? plate;
  String? vehiclePhotoUrl;

  String? get vehiclePlate => plate;
  String? get vehiclePhoto => vehiclePhotoUrl;

  LatLng? currentLocation;

  bool isLoading = true;
  bool loadingLocation = true;
  final List<SolicitudItem> solicitudes = [];
  StreamSubscription<QuerySnapshot>? _sub;

  // Método de inicialización principal
  Future<void> init() async {
    isLoading = true;
    loadingLocation = true;
    _safeNotify();
    _listenCachedName();
    // Kick off async startup tasks but do not await them so UI can render fast.
    _loadProfile();
    _requestBackgroundLocationPermission();
    _loadLocation();

    // Subscriptions can be registered immediately; they will react when data arrives.
    _subscribeConductorStatus();
    _subscribeSolicitudes();
    _subscribeRatings();

    // Mark initial loading as false to avoid blocking UI; specific flags (like loadingLocation)
    // remain true until their respective tasks complete and update the VM.
    isLoading = false;
    _safeNotify();
  }

  void _listenCachedName() {
    _cachedNameSub?.cancel();
    _cachedNameSub = SessionHelper.cachedNameStream.listen((name) {
      if (name != null && name.trim().isNotEmpty) {
        setDisplayName(name.trim());
      }
    });

    SessionHelper.getCachedName()
        .then((n) {
          if (n != null && n.trim().isNotEmpty) {
            setDisplayName(n.trim());
          }
        })
        .catchError((_) {});
  }

  Future<void> _loadProfile() async {
    // Cargar perfil (no solicitar ubicación aquí para evitar bloqueos duplicados)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        photoUrl = user.photoURL;
        if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
          displayName = user.displayName!.trim();
        } else if (user.email != null && user.email!.contains('@')) {
          final namePart = user.email!.split('@').first;
          if (namePart.isNotEmpty)
            displayName =
                '${namePart[0].toUpperCase()}${namePart.substring(1)}';
        }

        final uid = user.uid;
        try {
          final snap = await _firestore.collection('usuarios').doc(uid).get();
          if (snap.exists) {
            final data = snap.data();
            nameFromDb = data?['nombre']?.toString();
            plate = data?['placa']?.toString();
            // Preferir la foto almacenada en Firestore si existe
            final fotoFromDb =
                data?['fotoUrl'] ?? data?['foto'] ?? data?['photoUrl'];
            if (fotoFromDb != null && fotoFromDb.toString().trim().isNotEmpty) {
              photoUrl = fotoFromDb.toString().trim();
            }
            // Obtener la foto del vehículo si existe
            final fotoVehiculoFromDb =
                data?['fotoVehiculo'] ?? data?['vehiclePhotoUrl'];
            if (fotoVehiculoFromDb != null &&
                fotoVehiculoFromDb.toString().trim().isNotEmpty) {
              vehiclePhotoUrl = fotoVehiculoFromDb.toString().trim();
            }

            final docAverage = _toDoubleOrNull(
              data?['calificacionPromedio'] ??
                  data?['ratingPromedio'] ??
                  data?['rating'],
            );
            final docCount = _toIntOrNull(
              data?['totalCalificaciones'] ??
                  data?['ratingCount'] ??
                  data?['totalRatings'],
            );

            if (docAverage != null) {
              _ratingFromConductorDoc = docAverage.clamp(0.0, 5.0).toDouble();
            }
            if (docCount != null && docCount >= 0) {
              _totalRatingsFromConductorDoc = docCount;
            }
            if (_totalRatingsFromConductorDoc > 0) {
              totalRatings = _totalRatingsFromConductorDoc;
              rating = _ratingFromConductorDoc;
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
      }
    } catch (_) {}
    loadingLocation = false;
    _safeNotify();

    // Si ahora ya tenemos ubicación y el conductor está conectado, re-subscribimos
    // para asegurar que la lista de solicitudes se reevalúe con la distancia correcta.
    if (currentLocation != null && isConnected) {
      ensureSolicitudesSubscription();
    }
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
    unawaited(preloadClientePhoto(preview.solicitud.clienteId));
    _safeNotify();
  }

  String? fotoClientePorId(String? clienteId) {
    if (clienteId == null || clienteId.isEmpty) {
      return null;
    }
    return _clientePhotoById[clienteId];
  }

  Future<void> preloadClientePhoto(String? clienteId) async {
    if (clienteId == null || clienteId.isEmpty) return;
    if (_clientePhotoLoadedIds.contains(clienteId)) return;

    _clientePhotoLoadedIds.add(clienteId);
    try {
      final doc = await _firestore.collection('cliente').doc(clienteId).get();
      if (!doc.exists) {
        _safeNotify();
        return;
      }

      final data = doc.data();
      final foto =
          data?['foto']?.toString() ??
          data?['fotoUrl']?.toString() ??
          data?['photo']?.toString();

      if (foto != null && foto.isNotEmpty) {
        _clientePhotoById[clienteId] = foto;
      }
      _safeNotify();
    } catch (_) {
      _safeNotify();
    }
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
    // Ensure we don't keep an active listener when driver is disconnected.
    _sub?.cancel();
    if (!isConnected) {
      // Do not subscribe while disconnected.
      return;
    }

    // Suscribirse solo a solicitudes en estado "pendiente/buscando" para
    // reducir el volumen de datos descargados.
    _sub = _firestore
        .collection('solicitudes')
        .where('estado', whereIn: ['buscando', 'pending', 'pendiente'])
        .snapshots()
        .listen((snap) {
          _handleSolicitudesQuerySnapshot(snap);
        });
  }

  /// Asegura que el listener de solicitudes esté activo si el conductor está conectado.
  void ensureSolicitudesSubscription() {
    if (!isConnected) return;
    _subscribeSolicitudes();
  }

  void _handleSolicitudesQuerySnapshot(QuerySnapshot snap) {
    if (!isConnected) {
      return;
    }

    try {
      final currentPendingIds = <String>{};
      final parsedSolicitudes = <SolicitudItem>[];

      for (final doc in snap.docs) {
        final item = _buildPendingSolicitudItem(doc);
        if (item == null) continue;

        if (currentLocation != null) {
          item.distanciaKm = _distanceKm(
            currentLocation!.latitude,
            currentLocation!.longitude,
            item.ubicacionInicial.latitude,
            item.ubicacionInicial.longitude,
          );

          // Only include solicitudes within 3 km
          if (item.distanciaKm == null || item.distanciaKm! > 3.0) {
            continue;
          }

          // mark as pending for notification comparison (only when within range)
          currentPendingIds.add(doc.id);
        } else {
          // If current location is not yet available, keep solicitudes and show them.
          item.distanciaKm = null;
          currentPendingIds.add(doc.id);
        }

        parsedSolicitudes.add(item);
        unawaited(_completarDatosSolicitud(item));
        unawaited(_ensureFriendlyAddress(item));
      }

      solicitudes
        ..clear()
        ..addAll(parsedSolicitudes);

      try {
        for (final id in currentPendingIds) {
          if (!_knownPendingIds.contains(id)) {
            try {
              _newSolicitudController.add(id);
            } catch (_) {}
            try {
              NotificationService.instance.showNotification(
                id.hashCode & 0x7fffffff,
                'Solicitud entrante',
                'Cliente necesita servicio',
              );
            } catch (_) {}
          }
        }
        _knownPendingIds
          ..clear()
          ..addAll(currentPendingIds);
      } catch (_) {}

      solicitudes.sort(
        (a, b) => (a.distanciaKm ?? double.maxFinite).compareTo(
          b.distanciaKm ?? double.maxFinite,
        ),
      );
      _safeNotify();
    } catch (_) {}
  }

  SolicitudItem? _buildPendingSolicitudItem(QueryDocumentSnapshot doc) {
    final raw = doc.data();
    if (raw is! Map<String, dynamic>) return null;

    final status = raw['estado'] ?? raw['status'];
    if (!_isPendingStatus(status)) return null;

    final item = SolicitudItem.fromMap(doc.id, raw);
    if (item.clienteId == null || item.clienteId!.isEmpty) return null;

    final lat = item.ubicacionInicial.latitude;
    final lng = item.ubicacionInicial.longitude;
    if (lat == 0 && lng == 0) return null;

    return item;
  }

  bool _isPendingStatus(dynamic status) {
    if (status == null) return false;
    final normalized = status.toString().toLowerCase().trim();
    return normalized == 'buscando' ||
        normalized == 'pending' ||
        normalized == 'pendiente';
  }

  Future<void> _ensureFriendlyAddress(SolicitudItem item) async {
    final hasAddress =
        (item.origenTitle != null && item.origenTitle!.trim().isNotEmpty) ||
        (item.direccion != null && item.direccion!.trim().isNotEmpty);
    if (hasAddress) return;
    if (!_resolvingAddressSolicitudIds.add(item.id)) return;

    try {
      final placemarks = await placemarkFromCoordinates(
        item.ubicacionInicial.latitude,
        item.ubicacionInicial.longitude,
      );
      if (placemarks.isEmpty) return;

      final p = placemarks.first;
      final parts = [
        p.street?.trim(),
        p.subLocality?.trim(),
        p.locality?.trim(),
      ].whereType<String>().where((value) => value.isNotEmpty);

      final friendly = parts.take(2).join(', ').trim();
      if (friendly.isEmpty) return;

      item.origenTitle = friendly;
      item.direccion = friendly;
      _safeNotify();
    } catch (_) {
      // Si falla geocoding dejamos fallback a lat/lng en la vista.
    } finally {
      _resolvingAddressSolicitudIds.remove(item.id);
    }
  }

  void _subscribeConductorStatus() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _conductorSub?.cancel();
      _conductorSub = _firestore.collection('usuarios').doc(uid).snapshots().listen((
        snap,
      ) {
        if (!snap.exists) return;
        final data = snap.data();
        if (data != null) {
          final docName = data['nombre']?.toString().trim();
          if (docName != null && docName.isNotEmpty) {
            displayName = docName;
          }

          final docPlate = data['placa']?.toString().trim();
          if (docPlate != null && docPlate.isNotEmpty) {
            plate = docPlate;
          }

          final p = data['foto'] ?? data['fotoUrl'] ?? data['photoUrl'];
          if (p != null && p.toString().trim().isNotEmpty) {
            photoUrl = p.toString().trim();
          }

          final vehiclePhoto = data['fotoVehiculo'] ?? data['vehiclePhotoUrl'];
          if (vehiclePhoto != null &&
              vehiclePhoto.toString().trim().isNotEmpty) {
            vehiclePhotoUrl = vehiclePhoto.toString().trim();
          }

          final docAverage = _toDoubleOrNull(
            data['calificacionPromedio'] ??
                data['ratingPromedio'] ??
                data['rating'],
          );
          final docCount = _toIntOrNull(
            data['totalCalificaciones'] ??
                data['ratingCount'] ??
                data['totalRatings'],
          );

          if (docAverage != null) {
            _ratingFromConductorDoc = docAverage.clamp(0.0, 5.0).toDouble();
          }
          if (docCount != null && docCount >= 0) {
            _totalRatingsFromConductorDoc = docCount;
          }

          if (_totalRatingsFromConductorDoc > 0) {
            totalRatings = _totalRatingsFromConductorDoc;
            rating = _ratingFromConductorDoc;
          }
        }

        final connected =
            snap.exists &&
            ((snap.data()?['disponible'] == true) ||
                (snap.data()?['conectado'] == true));
        final previously = isConnected;
        isConnected = connected;
        if (!isConnected) {
          // Limpiar estados de solicitudes/previews cuando no está disponible.
          try {
            stopPreviewSolicitudStatusListener();
          } catch (_) {}
          clearPreviewAndRoutes();
          solicitudes.clear();
          _knownPendingIds.clear();
          // Cancel solicitudes listener when disconnected to avoid processing updates
          try {
            _sub?.cancel();
          } catch (_) {}
          _safeNotify();
        } else if (!previously && isConnected) {
          // Just became connected: start listening to solicitudes
          try {
            _subscribeSolicitudes();
          } catch (_) {}
        }
        _safeNotify();
      });
    } catch (_) {}
  }

  void _subscribeRatings() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _ratingSub?.cancel();
      _ratingSub = _firestore
          .collection('solicitudes')
          .where('conductor.id', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
            double scoreTotal = 0.0;
            int completedCount = 0;
            int ratedCount = 0;
            double serviceTotal = 0.0;

            for (var doc in snap.docs) {
              try {
                final data = doc.data();
                final estado = (data['estado'] ?? data['status'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim();
                if (!_isCompletedStatus(estado)) continue;

                completedCount++;
                serviceTotal += _extractServiceValue(data);

                final score = _extractRatingScore(data);
                if (score != null) {
                  scoreTotal += score;
                  ratedCount++;
                }
              } catch (_) {}
            }

            // Promedio basado en calificaciones efectivamente realizadas por clientes.
            totalCompletedTrips = completedCount;
            totalServiceValue = serviceTotal;
            // Si existe rating consolidado en usuarios, priorizarlo en la vista.
            if (_totalRatingsFromConductorDoc > 0) {
              totalRatings = _totalRatingsFromConductorDoc;
              rating = _ratingFromConductorDoc;
            } else if (ratedCount > 0) {
              totalRatings = ratedCount;
              rating = scoreTotal / ratedCount;
            } else {
              totalRatings = _totalRatingsFromConductorDoc;
              rating = _totalRatingsFromConductorDoc > 0
                  ? _ratingFromConductorDoc
                  : 0.0;
            }
            _safeNotify();
          });
    } catch (_) {}
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _toIntOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _isCompletedStatus(String status) {
    if (status.isEmpty) return false;
    return status == 'completado' || status.contains('complet');
  }

  double _extractServiceValue(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    if (tarifa is Map<String, dynamic> && tarifa['total'] != null) {
      final total = tarifa['total'];
      if (total is num) return total.toDouble();
      return double.tryParse(total.toString()) ?? 0.0;
    }

    final valor = data['valor'];
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  double? _extractRatingScore(Map<String, dynamic> data) {
    final raw = data['calificacion'] ?? data['calificacion_cliente'];
    if (raw is Map<String, dynamic>) {
      final score = raw['score'] ?? raw['puntaje'] ?? raw['valor'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '');
    }
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  Future<void> toggleConductorConnection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    isTogglingConnection = true;
    _safeNotify();
    try {
      final docRef = _firestore.collection('usuarios').doc(uid);
      final snap = await docRef.get();
      final data = snap.data();
      final current =
          snap.exists &&
          ((data?['disponible'] == true) || (data?['conectado'] == true));
      final newVal = !current;
      await docRef.set({
        'uid': uid,
        'rol': 'conductor',
        'tipoUsuario': 'conductor',
        'disponible': newVal,
      }, SetOptions(merge: true));
      // The _conductorSub listener will update the local isConnected state
    } catch (e) {
      debugPrint('Error toggling connection: $e');
      rethrow;
    } finally {
      isTogglingConnection = false;
      _safeNotify();
    }
  }

  Future<void> fetchRouteOSRM(String id, LatLng origin, LatLng dest) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = json.decode(resp.body) as Map<String, dynamic>?;
      if (data == null) return;
      final routesList = data['routes'] as List?;
      if (routesList == null || routesList.isEmpty) return;
      final geometry = routesList[0]['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['coordinates'] == null) return;
      final coords = geometry['coordinates'] as List;
      final points = coords.map<LatLng>((c) {
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      setRoute(id, points);
    } catch (e) {
      debugPrint('Error fetching route OSRM: $e');
    }
  }

  Future<void> aceptarSolicitud(String solicitudId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No user logged in');

    await _firestore.collection('solicitudes').doc(solicitudId).update({
      'estado': 'asignado',
      'conductor': {
        'id': uid,
        'nombre': displayName,
        if (photoUrl != null) 'foto': photoUrl,
        'placa': vehiclePlate ?? '',
        if (currentLocation != null) 'lat': currentLocation!.latitude,
        if (currentLocation != null) 'lng': currentLocation!.longitude,
        if (vehiclePhotoUrl != null) 'fotoVehiculo': vehiclePhotoUrl,
      },
      'fecha de aceptacion conductor': FieldValue.serverTimestamp(),
    });
  }

  Future<void> listenPreviewSolicitudStatus({
    required String solicitudId,
    required Future<void> Function() onCanceladoOrRemoved,
    required Future<void> Function() onAsignado,
  }) async {
    await stopPreviewSolicitudStatusListener();
    _previewStatusHandled = false;

    _previewStatusSub = _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((snap) async {
          try {
            if (_previewStatusHandled) return;

            if (!snap.exists) {
              _previewStatusHandled = true;
              await onCanceladoOrRemoved();
              return;
            }

            final data = snap.data();
            final status = data?['estado'] ?? data?['status'];
            if (status is! String) return;

            final sLower = status.toLowerCase();
            if (sLower.contains('cancelado') || sLower.contains('anulad')) {
              _previewStatusHandled = true;
              await onCanceladoOrRemoved();
              return;
            }

            if (sLower.contains('asignado')) {
              _previewStatusHandled = true;
              await onAsignado();
              return;
            }
          } catch (_) {}
        });
  }

  Future<void> stopPreviewSolicitudStatusListener() async {
    final sub = _previewStatusSub;
    _previewStatusSub = null;
    _previewStatusHandled = false;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (_) {}
  }

  double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }

  Future<void> _completarDatosSolicitud(SolicitudItem item) async {
    try {
      if (item.nombreCliente == null) {
        final cli = await _firestore
            .collection('cliente')
            .doc(item.clienteId)
            .get();
        item.nombreCliente = cli.data()?['nombre']?.toString() ?? 'Cliente';
      }
      if (item.direccion == null) {
        item.direccion = 'Ubicación del cliente';
      }
      _safeNotify();
    } catch (_) {}
  }

  SolicitudItem? get firstSolicitud =>
      solicitudes.isNotEmpty ? solicitudes.first : null;

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  /// Centra la cámara del mapa en `currentLocation` si está disponible.
  ///
  /// Pasa el `GoogleMapController` activo y opcionalmente el nivel de zoom.
  Future<void> centerMapOnMarker(
    GoogleMapController controller, {
    double zoom = 15.0,
  }) async {
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
    try {
      _ratingSub?.cancel();
    } catch (_) {}
    try {
      _conductorSub?.cancel();
    } catch (_) {}
    try {
      _previewStatusSub?.cancel();
    } catch (_) {}
    try {
      _cachedNameSub?.cancel();
    } catch (_) {}
    try {
      _newSolicitudController.close();
    } catch (_) {}
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Actualiza el nombre de display y notifica a los listeners de forma segura.
  void setDisplayName(String name) {
    displayName = name;
    _safeNotify();
  }
}
