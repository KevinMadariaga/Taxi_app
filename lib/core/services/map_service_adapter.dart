import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/map_service.dart'
    as feature_map;

/// Compatibility adapter that exposes the legacy `MapService` API while
/// delegating routing/distance/eta work to the newer feature implementation.
class MapService {
  const MapService();

  // Instancia compartida: el caché de ruta de 8s de feature_map.MapService
  // vive en el objeto, no en la clase. Crear una nueva por cada llamada (como
  // se hacía antes) anulaba ese caché y disparaba una petición HTTP nueva a
  // Directions/OSRM en cada tick de tracking aunque el punto casi no se
  // hubiera movido.
  static final feature_map.MapService _f = feature_map.MapService();

  Future<int?> calcularTiempoEstimado(LatLng origin, LatLng destination) async {
    try {
      final pts = await _f.fetchRoadPolyline(from: origin, to: destination);
      final dist = _f.routeDistanceMeters(pts);
      final dur = _f.etaFromDistance(dist);
      return dur.inSeconds;
    } catch (_) {
      return null;
    }
  }

  Future<List<LatLng>> getRoutePolyline(
    LatLng origin,
    LatLng destination,
  ) async {
    return await _f.fetchRoadPolyline(from: origin, to: destination);
  }

  double calcularDistanciaPolyline(List<LatLng> polyline) {
    return _f.routeDistanceMeters(polyline);
  }

  Stream<String?> escucharEstadoSolicitudStream(String solicitudId) {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['estado'] as String?);
  }

  CameraUpdate cameraToPosition(LatLng target, {double zoom = 16}) {
    return CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: zoom),
    );
  }

  LatLngBounds? computeBoundsFromPoints(List<LatLng> points) {
    if (points.isEmpty) return null;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  CameraUpdate? cameraToBoundsFromPoints(
    List<LatLng> points, {
    double padding = 80,
  }) {
    final bounds = computeBoundsFromPoints(points);
    if (bounds == null) return null;
    return CameraUpdate.newLatLngBounds(bounds, padding);
  }

  CameraUpdate? cameraToBoundsFromMarkers(
    Set<Marker> markers, {
    double padding = 80,
  }) {
    if (markers.isEmpty) return null;
    final points = markers.map((m) => m.position).toList();
    return cameraToBoundsFromPoints(points, padding: padding);
  }

  Marker createMarker({
    required String id,
    required LatLng position,
    String? title,
    String? snippet,
    BitmapDescriptor? icon,
    bool draggable = false,
  }) {
    return Marker(
      markerId: MarkerId(id),
      position: position,
      infoWindow: InfoWindow(title: title, snippet: snippet),
      icon: icon ?? BitmapDescriptor.defaultMarker,
      draggable: draggable,
    );
  }

  Polyline createPolyline({
    required String id,
    required List<LatLng> points,
    Color color = Colors.blue,
    int width = 4,
    bool geodesic = true,
  }) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: color,
      width: width,
      geodesic: geodesic,
    );
  }

  List<LatLng> decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Future<Polyline?> createPolylineFromDirections({
    required String id,
    required LatLng origin,
    required LatLng destination,
    Color color = Colors.blue,
    int width = 4,
    bool geodesic = true,
  }) async {
    final pts = await _f.fetchRoadPolyline(from: origin, to: destination);
    if (pts.isEmpty) return null;
    return createPolyline(
      id: id,
      points: pts,
      color: color,
      width: width,
      geodesic: geodesic,
    );
  }
}
