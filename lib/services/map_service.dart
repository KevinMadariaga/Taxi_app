import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Servicio utilitario para operaciones de mapa (cámara, marcadores,
/// polilíneas y bounds).
///
/// Mantiene a los widgets como `AppGoogleMap` enfocados sólo en la UI,
/// mientras que la lógica de posicionamiento y construcción de overlays
/// vive aquí o en los ViewModels.
class MapService {
	const MapService();

	/// Construye un [CameraUpdate] para centrar la cámara en una posición
	/// específica con un zoom dado.
	CameraUpdate cameraToPosition(LatLng target, {double zoom = 16}) {
		return CameraUpdate.newCameraPosition(
			CameraPosition(target: target, zoom: zoom),
		);
	}

	/// Calcula bounds a partir de una lista de puntos y devuelve el
	/// [LatLngBounds]. Retorna null si la lista está vacía.
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

	/// Devuelve un [CameraUpdate] para ajustar la cámara a los bounds
	/// calculados a partir de una lista de puntos.
	CameraUpdate? cameraToBoundsFromPoints(
		List<LatLng> points, {
		double padding = 80,
	}) {
		final bounds = computeBoundsFromPoints(points);
		if (bounds == null) return null;
		return CameraUpdate.newLatLngBounds(bounds, padding);
	}

	/// Devuelve un [CameraUpdate] para ajustar la cámara a los bounds
	/// calculados a partir de un conjunto de marcadores.
	CameraUpdate? cameraToBoundsFromMarkers(
		Set<Marker> markers, {
		double padding = 80,
	}) {
		if (markers.isEmpty) return null;
		final points = markers.map((m) => m.position).toList();
		return cameraToBoundsFromPoints(points, padding: padding);
	}

	/// Crea un marcador a partir de parámetros comunes.
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
			infoWindow: InfoWindow(
				title: title,
				snippet: snippet,
			),
			icon: icon ?? BitmapDescriptor.defaultMarker,
			draggable: draggable,
		);
	}

	/// Crea una polilínea estándar para representar rutas.
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
}

