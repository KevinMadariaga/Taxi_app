import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Helper para lógica de mapa que no depende de la UI:
///
/// - Carga de íconos personalizados
/// - Cálculo de distancias
/// - Cálculo de rumbos (bearing)
/// - Distancia total de una ruta
class MapHelper {
	MapHelper._();

	/// Carga un ícono de marcador desde assets con un tamaño y DPR razonables.
	static Future<BitmapDescriptor> loadMarkerIcon(
		String assetPath, {
		Size size = const Size(48, 48),
		double? devicePixelRatio,
	}) async {
		// Use a neutral devicePixelRatio for marker generation by default to avoid
		// producing oversized icons on high-density iOS displays. Callers may
		// still override `devicePixelRatio` when needed.
		final usedDpr = devicePixelRatio ?? 1.0;
		return BitmapDescriptor.fromAssetImage(
			ImageConfiguration(size: size, devicePixelRatio: usedDpr),
			assetPath,
		);
	}

	/// Distancia en metros entre dos puntos usando Geolocator.
	static double distanceMeters(LatLng from, LatLng to) {
		return Geolocator.distanceBetween(
			from.latitude,
			from.longitude,
			to.latitude,
			to.longitude,
		);
	}

	/// Distancia total en metros de una lista de puntos (ruta polilínea).
	static double routeDistanceMeters(List<LatLng> points) {
		if (points.length < 2) return 0;
		double total = 0;
		for (var i = 0; i < points.length - 1; i++) {
			total += distanceMeters(points[i], points[i + 1]);
		}
		return total;
	}

	/// Calcula el rumbo (bearing) en grados desde `from` hacia `to`.
	/// Devuelve un valor en [0, 360).
	static double bearingDegrees(LatLng from, LatLng to) {
		final lat1 = from.latitude * math.pi / 180;
		final lat2 = to.latitude * math.pi / 180;
		final dLon = (to.longitude - from.longitude) * math.pi / 180;
		final y = math.sin(dLon) * math.cos(lat2);
		final x = math.cos(lat1) * math.sin(lat2) -
				math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
		final brng = math.atan2(y, x);
		return (brng * 180 / math.pi + 360) % 360;
	}
}

