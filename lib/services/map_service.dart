import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'DireccionesServicio.dart';
import 'dart:math' as math;

/// Servicio utilitario para operaciones de mapa (cámara, marcadores,
/// polilíneas y bounds).
///
/// Mantiene a los widgets como `AppGoogleMap` enfocados sólo en la UI,
/// mientras que la lógica de posicionamiento y construcción de overlays
/// vive aquí o en los ViewModels.
class MapService {

	/// Calcula el tiempo estimado (en segundos) entre dos ubicaciones usando la API de direcciones.
	Future<int?> calcularTiempoEstimado(LatLng origin, LatLng destination) async {
		final direcciones = Direcciones();
		return await direcciones.getEstimatedDuration(
			origin.latitude,
			origin.longitude,
			destination.latitude,
			destination.longitude,
		);
	}

		/// Obtiene la polyline (lista de LatLng) entre dos puntos usando la API de direcciones.
		/// Si la API falla, retorna una línea recta entre ambos.
		Future<List<LatLng>> getRoutePolyline(LatLng origin, LatLng destination) async {
			final polyline = await createPolylineFromDirections(
				id: 'route',
				origin: origin,
				destination: destination,
			);
			if (polyline != null && polyline.points.isNotEmpty) {
				return polyline.points;
			}
			// Si falla, retorna línea recta
			return [origin, destination];
		}

		/// Calcula la distancia total de una polyline (en metros).
		double calcularDistanciaPolyline(List<LatLng> polyline) {
			if (polyline.length < 2) return 0.0;
			double total = 0.0;
			for (int i = 1; i < polyline.length; i++) {
				total += _distanceBetween(polyline[i - 1], polyline[i]);
			}
			return total;
		}

		/// Calcula la distancia entre dos puntos (en metros) usando la fórmula de Haversine.
		double _distanceBetween(LatLng a, LatLng b) {
			const R = 6371000; // Radio de la Tierra en metros
			final dLat = _degToRad(b.latitude - a.latitude);
			final dLng = _degToRad(b.longitude - a.longitude);
			final lat1 = _degToRad(a.latitude);
			final lat2 = _degToRad(b.latitude);
			final aVal =
					math.sin(dLat / 2) * math.sin(dLat / 2) +
					math.cos(lat1) * math.cos(lat2) *
							math.sin(dLng / 2) * math.sin(dLng / 2);
			final c = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
			return R * c;
		}

		double _degToRad(double deg) => deg * (math.pi / 180.0);
	const MapService();

	/// Escucha el estado de la solicitud en Firestore y emite los cambios.
	/// Retorna un Stream<String?> con el estado actual de la solicitud.
	Stream<String?> escucharEstadoSolicitudStream(String solicitudId) {
		// Requiere importar cloud_firestore en el archivo donde se use este método.
		return FirebaseFirestore.instance
				.collection('solicitudes')
				.doc(solicitudId)
				.snapshots()
				.map((snapshot) => snapshot.data()?['estado'] as String?);
	}

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

	/// Decodifica una polyline codificada de Google Directions API a una lista de LatLng.
	List<LatLng> decodePolyline(String encoded) {
		List<LatLng> poly = [];
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

	/// Obtiene una Polyline desde la API de direcciones de Google Directions.
	/// Retorna null si falla la petición o el decodificado.
	Future<Polyline?> createPolylineFromDirections({
		required String id,
		required LatLng origin,
		required LatLng destination,
		Color color = Colors.blue,
		int width = 4,
		bool geodesic = true,
	}) async {
		final direcciones = Direcciones();
		final encoded = await direcciones.getPolyline(
			origin.latitude,
			origin.longitude,
			destination.latitude,
			destination.longitude,
		);
		if (encoded == null || encoded.isEmpty) return null;
		final points = decodePolyline(encoded);
		if (points.isEmpty) return null;
		return createPolyline(
			id: id,
			points: points,
			color: color,
			width: width,
			geodesic: geodesic,
		);
	}
}

