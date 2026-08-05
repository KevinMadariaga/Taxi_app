import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';

/// Preview de una solicitud seleccionada + su ruta en el mapa.
///
/// Extraído de InicioConductorViewmodel (comunidad de menor cohesión del
/// repo según graphify-out/GRAPH_REPORT.md) — pieza sin listeners de
/// Firestore propios (solo una lectura puntual para la foto del cliente),
/// autocontenida salvo por `currentLocation`, que sigue siendo del vm host
/// (dueño real del GPS del conductor) y se accede vía [getCurrentLocation].
class PreviewRouteController {
  PreviewRouteController({
    required FirebaseFirestore firestore,
    required TrackingService trackingService,
  }) : _firestore = firestore,
       _trackingService = trackingService;

  final FirebaseFirestore _firestore;
  final TrackingService _trackingService;

  PreviewSolicitud? selectedPreview;
  bool isMapExpanded = false;
  final Map<String, List<LatLng>> routePoints = {};
  final Set<Polyline> routePolylines = {};
  final Set<Marker> extraMarkers = {};
  bool isLoadingPreviewRoute = false;

  final Map<String, String> _clientePhotoById = {};
  final Set<String> _clientePhotoLoadedIds = {};

  /// Se dispara con cada cambio de estado — el vm host lo usa para su propio
  /// notifyListeners.
  VoidCallback? onChanged;

  /// La ubicación actual del conductor la posee el vm host (es del GPS del
  /// conductor, no de la preview). Se lee vía callback en vez de duplicarla.
  LatLng? Function()? getCurrentLocation;

  /// `fetchRouteOSRM` puede refrescar la ubicación (ver comentario original:
  /// `currentLocation` queda obsoleta en sesiones largas conectado) — se
  /// reporta de vuelta al vm host, dueño real de ese estado.
  void Function(LatLng)? onLocationRefreshed;

  void selectPreview(PreviewSolicitud preview) {
    selectedPreview = preview;
    isMapExpanded = false;
    unawaited(preloadClientePhoto(preview.solicitud.clienteId));
    // Si el item se armó antes de tener currentLocation (p. ej. justo tras un
    // cambio de rol, cuando el GPS aún no resolvía), su distanciaKm quedó en
    // null. Recalcularla aquí evita que la preview muestre "Solicitud cercana"
    // genérico en vez de la distancia real.
    refreshSelectedPreviewDistance();
    onChanged?.call();
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
        onChanged?.call();
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
      onChanged?.call();
    } catch (_) {
      onChanged?.call();
    }
  }

  void clearPreviewAndRoutes() {
    selectedPreview = null;
    isMapExpanded = false;
    routePoints.clear();
    routePolylines.removeWhere((p) => p.polylineId.value.startsWith('route_'));
    extraMarkers.removeWhere((m) => m.markerId.value == 'driver');
    onChanged?.call();
  }

  void setMapExpanded(bool value) {
    if (isMapExpanded == value) return;
    isMapExpanded = value;
    onChanged?.call();
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
    onChanged?.call();
  }

  /// Recalcula la distancia de la preview abierta contra la ubicación actual
  /// del conductor.
  ///
  /// `selectedPreview` guarda una referencia fija al `SolicitudItem` del
  /// momento en que se abrió: cada snapshot nuevo de `solicitudes` crea
  /// objetos `SolicitudItem` nuevos, así que la distancia de la preview
  /// abierta jamás se actualizaba sola. Necesario tras volver de un
  /// background prolongado (la ubicación se refresca pero la preview no).
  void refreshSelectedPreviewDistance() {
    final preview = selectedPreview;
    final loc = getCurrentLocation?.call();
    if (preview == null || loc == null) return;
    preview.solicitud.distanciaKm = _distanceKm(
      loc.latitude,
      loc.longitude,
      preview.solicitud.ubicacionInicial.latitude,
      preview.solicitud.ubicacionInicial.longitude,
    );
    onChanged?.call();
  }

  /// Refleja localmente una contraoferta recién enviada, sin esperar el
  /// round-trip del listener de Firestore (que puede tardar y deja la
  /// tarjeta mostrando el precio viejo justo después de que el conductor
  /// confirma el envío).
  void applyLocalContraoferta(double valor) {
    final preview = selectedPreview;
    if (preview == null) return;
    preview.solicitud.valorContraoferta = valor;
    preview.solicitud.estadoContraoferta = 'pendiente_cliente';
    onChanged?.call();
  }

  Future<void> fetchRouteOSRM(String id, LatLng origin, LatLng dest) async {
    isLoadingPreviewRoute = true;
    onChanged?.call();
    try {
      // `currentLocation` se carga una sola vez al construir el vm host (ver
      // `_loadLocation`) y nunca se refresca — en una sesión larga de
      // conductor (horas conectado, maneja kilómetros) queda obsoleta. Si al
      // abrir un preview de solicitud se usa ese `origin` viejo tal cual, la
      // ruta calculada parte de un punto que ya no es real: puede rendear
      // fuera del viewport centrado en el cliente (se ve como si "no
      // apareciera la traza") o directamente fallar. Se refresca el origen
      // justo antes de pedir la ruta; si el refresh falla, se sigue con el
      // `origin` recibido como fallback en vez de bloquear el preview.
      var effectiveOrigin = origin;
      try {
        final fresh = await _trackingService.obtenerUbicacionActual();
        if (fresh != null) {
          effectiveOrigin = LatLng(fresh.latitude, fresh.longitude);
          onLocationRefreshed?.call(effectiveOrigin);
        }
      } catch (_) {
        // Se sigue con `origin` (posiblemente obsoleto) como fallback.
      }

      final mapService = const MapService();
      final points = await mapService.getRoutePolyline(effectiveOrigin, dest);
      if (points.isNotEmpty) {
        setRoute(id, points);
      }
    } catch (e, st) {
      developer.log(
        'Fallo al calcular ruta de preview (sin traza para esta solicitud): $e',
        name: 'InicioConductorViewModel',
        level: 1000,
      );
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'InicioConductorViewModel: fallo fetchRouteOSRM (preview sin ruta)',
      );
    } finally {
      isLoadingPreviewRoute = false;
      onChanged?.call();
    }
  }

  CameraPosition? getCameraPerspectiveForPreview() {
    final preview = selectedPreview;
    final loc = getCurrentLocation?.call();
    if (preview == null || loc == null) return null;
    final s = preview.solicitud;
    final client = LatLng(
      s.ubicacionInicial.latitude,
      s.ubicacionInicial.longitude,
    );
    final driver = loc;
    final bearing = calculateBearing(driver, client);
    return CameraPosition(
      target: driver,
      bearing: bearing,
      tilt: 10.0,
      zoom: 16.0,
    );
  }

  double calculateBearing(LatLng from, LatLng to) =>
      MapHelper.bearingDegrees(from, to);

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      MapHelper.distanceMeters(LatLng(lat1, lon1), LatLng(lat2, lon2)) / 1000;
}
