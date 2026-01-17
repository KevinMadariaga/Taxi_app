import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/resumen_cliente_view.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// Vista para el cliente cuando ya va rumbo al destino.
/// Muestra la ruta entre el conductor y el destino, con zoom/bearing dinámico
/// y recorte progresivo de la polilínea a medida que el conductor avanza.
class RutaDestinoClienteView extends StatefulWidget {
	final String solicitudId;
	final LatLng? destinoLocation;

	const RutaDestinoClienteView({Key? key, required this.solicitudId, this.destinoLocation}) : super(key: key);

	@override
	State<RutaDestinoClienteView> createState() => _RutaDestinoClienteViewState();
}

class _RutaDestinoClienteViewState extends State<RutaDestinoClienteView> {
	GoogleMapController? _mapController;
	LatLng? _driverLocation;
	LatLng? _destinoLocation;
	BitmapDescriptor? _driverIcon;
	BitmapDescriptor? _destinoIcon;
	Set<Polyline> _polylines = {};
	List<LatLng> _routePoints = [];
	int _lastRouteCutIndex = 0;

	StreamSubscription<LatLng>? _driverSub;
	StreamSubscription<String?>? _estadoSub;
	bool _loading = true;
	bool _terminandoDialogoMostrado = false;
	final FirebaseService _firebaseService = FirebaseService();

	String? _conductorNombre;
	String? _conductorFoto;
	String? _destinoTitulo;
	String? _conductorPlaca;
	String? _conductorId;

	@override
	void initState() {
		super.initState();
		_destinoLocation = widget.destinoLocation;
		_loadIcons();
 		_ensureDatos();
		_subscribeDriver();
		_subscribeEstado();
	}


	Future<void> _loadIcons() async {
		try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final driver = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/taxi_icon.png',
      );
			final destino = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
			if (!mounted) return;
			setState(() {
				_driverIcon = driver;
				_destinoIcon = destino;
			});
		} catch (_) {}
	}

	Future<void> _ensureDatos() async {
		try {
			final snap = await FirebaseFirestore.instance.collection('solicitudes').doc(widget.solicitudId).get();
			final data = snap.data();
			if (data != null) {
				// destino
				LatLng? destino;
				final rawDestino = data['destino'] ?? data['destination'];
				if (rawDestino is Map) {
					final u = (rawDestino['ubicacion'] ?? rawDestino);
					if (u is Map) {
						final lat = (u['lat'] ?? u['latitude'] ?? u['latitud']);
						final lng = (u['lng'] ?? u['longitude'] ?? u['longitud']);
						if (lat != null && lng != null) {
							destino = LatLng((lat as num).toDouble(), (lng as num).toDouble());
						}
					}
					final titulo = rawDestino['title'] ?? rawDestino['direccion'] ?? rawDestino['address'];
					if (titulo is String && titulo.trim().isNotEmpty) {
						_destinoTitulo = titulo.trim();
					}
				}

				// conductor
				final rawConductor = data['conductor'];
				if (rawConductor is Map) {
					final id = rawConductor['id'] ?? rawConductor['conductorId'];
					final nombre = rawConductor['nombre'] ?? rawConductor['name'];
					final foto = rawConductor['foto'] ?? rawConductor['photo'] ?? rawConductor['photoUrl'] ?? rawConductor['imagen'];
					final placa = rawConductor['placa'] ?? rawConductor['plate'] ?? rawConductor['licensePlate'];
					if (id is String) _conductorId = id.trim();
					if (nombre is String) _conductorNombre = nombre.trim();
					if (foto is String) _conductorFoto = foto.trim();
					if (foto is Map) {
						final url = foto['url'] ?? foto['link'];
						if (url is String) _conductorFoto = url.trim();
					}
					if (placa is String) _conductorPlaca = placa.trim();
				}

				if (destino != null && _destinoLocation == null) {
					_destinoLocation = destino;
				}
			}
		} catch (_) {}
		if (mounted) setState(() => _loading = false);
	}

	void _subscribeDriver() {
		_driverSub?.cancel();
		_driverSub = FirebaseFirestore.instance
				.collection('solicitudes')
				.doc(widget.solicitudId)
				.snapshots()
				.map((snap) {
					final d = snap.data();
					if (d == null) return null;
					final c = d['conductor'];
					if (c is Map) {
						final lat = (c['lat'] ?? c['latitude'] ?? c['latitud']);
						final lng = (c['lng'] ?? c['longitude'] ?? c['longitud']);
						if (lat != null && lng != null) {
							return LatLng((lat as num).toDouble(), (lng as num).toDouble());
						}
					}
					return null;
				})
				.where((p) => p != null)
				.cast<LatLng>()
				.listen((pos) {
					_driverLocation = pos;
					if (_driverLocation != null && _destinoLocation != null) {
						if (_routePoints.isEmpty) {
							_fetchRouteOSRM(_driverLocation!, _destinoLocation!);
						} else {
							_shortenRouteToDriver();
						}
					}
					setState(() {});
				}, onError: (_) {});
	}

	void _subscribeEstado() {
		_estadoSub?.cancel();
		_estadoSub = _firebaseService
				.escucharEstadoViaje(widget.solicitudId)
				.listen((estado) {
					final e = estado?.toLowerCase().trim();
					if (e == null) return;
					// Detectar variantes como "terminado", "terminando", "completado", "completada", "finalizado"
					if (e.contains('termin') || e.contains('complet') || e == 'finalizado') {
						if (!mounted) return;
						if (_terminandoDialogoMostrado) return;
						_terminandoDialogoMostrado = true;
						_mostrarViajeTerminado();
					}
				}, onError: (_) {});
	}

	void _mostrarViajeTerminado() {
		// Limpiar cache de solicitud activa antes de mostrar diálogo
		try { RouteCacheService.clearSolicitud(widget.solicitudId); } catch (_) {}
		showDialog(
			context: context,
			barrierDismissible: false,
			builder: (ctx) {
				return WillPopScope(
					onWillPop: () async => false,
					child: Dialog(
						backgroundColor: Colors.transparent,
						child: Column(
							mainAxisAlignment: MainAxisAlignment.center,
							children: [
								Container(
									padding: const EdgeInsets.all(32),
									decoration: BoxDecoration(
										color: Colors.white,
										borderRadius: BorderRadius.circular(16),
										boxShadow: [
											BoxShadow(
												color: Colors.black.withOpacity(0.1),
												blurRadius: 16,
												offset: const Offset(0, 4),
											),
										],
									),
									child: Column(
										mainAxisSize: MainAxisSize.min,
										children: [
											const SizedBox(
												width: 64,
												height: 64,
												child: CircularProgressIndicator(
													valueColor: AlwaysStoppedAnimation<Color>(AppColores.primary),
													strokeWidth: 3,
												),
											),
											const SizedBox(height: 24),
											const Text(
												'Viaje Terminado',
												style: TextStyle(
													fontSize: 22,
													fontWeight: FontWeight.w700,
													color: Colors.black87,
												),
											),
											const SizedBox(height: 8),
											Text(
												'Por favor espere...',
												style: TextStyle(
													fontSize: 14,
													color: Colors.grey.shade600,
												),
											),
										],
									),
								),
							],
						),
					),
				);
			},
		);

		Future.delayed(const Duration(seconds: 3), () {
			if (!mounted) return;
			Navigator.of(context).pushAndRemoveUntil(
				MaterialPageRoute(
					builder: (_) => ResumenClienteView(solicitudId: widget.solicitudId),
				),
				(route) => false,
			);
		});
	}

	@override
	void dispose() {
		_driverSub?.cancel();
		_estadoSub?.cancel();
		_mapController?.dispose();
		super.dispose();
	}

	void _onMapCreated(GoogleMapController controller) {
		_mapController = controller;
		if (_driverLocation != null && _destinoLocation != null) {
			_fetchRouteOSRM(_driverLocation!, _destinoLocation!);
		} else {
			_maybeUpdateCamera();
		}
	}

	void _maybeUpdateCamera() async {
		if (_mapController == null) return;
		final a = _driverLocation;
		final b = _destinoLocation;
		if (a == null || b == null) return;
		try {
			if (_routePoints.length >= 2) {
				final bearing = _calculateBearing(a, b);
				final dist = _haversineDistanceMeters(a, b);
				final zoom = _zoomForDistanceMeters(dist);
				await _mapController!.animateCamera(
					CameraUpdate.newCameraPosition(
						CameraPosition(target: a, zoom: zoom, bearing: bearing, tilt: 45),
					),
				);
			} else {
				final bounds = LatLngBounds(
					southwest: LatLng(
						math.min(a.latitude, b.latitude),
						math.min(a.longitude, b.longitude),
					),
					northeast: LatLng(
						math.max(a.latitude, b.latitude),
						math.max(a.longitude, b.longitude),
					),
				);
				await _mapController!.animateCamera(
					CameraUpdate.newLatLngBounds(bounds, 120),
				);
			}
		} catch (_) {}
	}

	double _haversineDistanceMeters(LatLng a, LatLng b) {
		const R = 6371000.0;
		final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
		final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
		final lat1 = a.latitude * math.pi / 180.0;
		final lat2 = b.latitude * math.pi / 180.0;
		final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
				math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
		final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
		return R * c;
	}

	double _zoomForDistanceMeters(double meters) {
		if (meters < 200) return 18;
		if (meters < 500) return 17;
		if (meters < 1000) return 16;
		if (meters < 2000) return 15;
		if (meters < 5000) return 14;
		if (meters < 10000) return 13;
		return 12;
	}

	double _calculateBearing(LatLng from, LatLng to) {
		final lat1 = from.latitude * math.pi / 180;
		final lat2 = to.latitude * math.pi / 180;
		final dLon = (to.longitude - from.longitude) * math.pi / 180;
		final y = math.sin(dLon) * math.cos(lat2);
		final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
		final brng = math.atan2(y, x);
		return (brng * 180 / math.pi + 360) % 360;
	}

	Future<void> _fetchRouteOSRM(LatLng origin, LatLng dest) async {
		try {
			final url = Uri.parse(
				'https://router.project-osrm.org/route/v1/driving/'
				'${origin.longitude},${origin.latitude};'
				'${dest.longitude},${dest.latitude}'
				'?overview=full&geometries=geojson',
			);
			final resp = await http.get(url).timeout(const Duration(seconds: 6));
			if (resp.statusCode != 200) return;
			final data = json.decode(resp.body) as Map<String, dynamic>?;
			if (data == null) return;
			final routes = data['routes'] as List?;
			if (routes == null || routes.isEmpty) return;
			final route0 = routes[0] as Map<String, dynamic>;
			final geometry = route0['geometry'] as Map<String, dynamic>?;
			if (geometry == null || geometry['coordinates'] == null) return;
			final coords = geometry['coordinates'] as List;
			final points = coords.map<LatLng>((c) {
				final lon = (c[0] as num).toDouble();
				final lat = (c[1] as num).toDouble();
				return LatLng(lat, lon);
			}).toList();

			if (!mounted) return;
			setState(() {
				final newPolys = Set<Polyline>.from(_polylines);
				newPolys.removeWhere((p) => p.polylineId.value == 'route');
				newPolys.add(
					Polyline(
						polylineId: const PolylineId('route'),
						color: AppColores.primary,
						width: 5,
						points: points,
					),
				);
				_polylines = newPolys;
				_routePoints = points;
				_lastRouteCutIndex = 0;
			});

			if (_mapController != null && points.isNotEmpty) {
				final bearing = _calculateBearing(origin, dest);
				final dist = _haversineDistanceMeters(origin, dest);
				final zoom = _zoomForDistanceMeters(dist);
				await _mapController!.animateCamera(
					CameraUpdate.newCameraPosition(
						CameraPosition(target: origin, zoom: zoom, bearing: bearing, tilt: 45),
					),
				);
			}
		} catch (_) {}
	}

	void _shortenRouteToDriver() {
		try {
			if (_routePoints.isEmpty || _driverLocation == null) return;

			final dest = _destinoLocation;
			if (dest != null) {
				final distToDest = _haversineDistanceMeters(_driverLocation!, dest);
				if (distToDest < 35) {
					setState(() {
						_routePoints = [];
						_polylines = _polylines.where((p) => p.polylineId.value != 'route').toSet();
					});
					return;
				}
			}

			int closestIdx = 0;
			double minDist = double.infinity;
			for (int i = 0; i < _routePoints.length; i++) {
				final d = _haversineDistanceMeters(_driverLocation!, _routePoints[i]);
				if (d < minDist) {
					minDist = d;
					closestIdx = i;
				}
			}

			if (closestIdx <= _lastRouteCutIndex) {
				_maybeUpdateCamera();
				return;
			}
			_lastRouteCutIndex = closestIdx;

			final startIdx = (closestIdx - 1).clamp(0, _routePoints.length - 1);
			final remaining = _routePoints.sublist(startIdx);

			setState(() {
				final newPolys = Set<Polyline>.from(_polylines);
				newPolys.removeWhere((p) => p.polylineId.value == 'route');
				if (remaining.length >= 2) {
					newPolys.add(
						Polyline(
							polylineId: const PolylineId('route'),
							color: AppColores.primary,
							width: 5,
							points: remaining,
						),
					);
				}
				_polylines = newPolys;
				_routePoints = remaining;
			});

			if (_mapController != null && _routePoints.length >= 2) {
				final nextPoint = _routePoints[1];
				final bearing = _calculateBearing(_driverLocation!, nextPoint);
				final dist = _haversineDistanceMeters(_driverLocation!, nextPoint);
				final zoom = _zoomForDistanceMeters(dist);
				_mapController!.animateCamera(
					CameraUpdate.newCameraPosition(
						CameraPosition(target: _driverLocation!, zoom: zoom, bearing: bearing, tilt: 45),
					),
				);
			}
		} catch (_) {}
	}

	@override
	Widget build(BuildContext context) {
		if (_loading) {
			return const Scaffold(
				backgroundColor: Colors.white,
				body: SafeArea(
					child: Center(
						child: MapLoadingWidget(message: 'Preparando ruta al destino...'),
					),
				),
			);
		}

		final markers = <Marker>{};
		if (_driverLocation != null && _driverIcon != null) {
			markers.add(
				Marker(
					markerId: const MarkerId('driver'),
					position: _driverLocation!,
					icon: _driverIcon!,
					infoWindow: const InfoWindow(title: 'Conductor'),
				),
			);
		}
		if (_destinoLocation != null) {
			markers.add(
				Marker(
					markerId: const MarkerId('destino'),
					position: _destinoLocation!,
					icon: _destinoIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
					infoWindow: const InfoWindow(title: 'Destino'),
				),
			);
		}

		final initialTarget = _driverLocation ?? _destinoLocation ?? const LatLng(0, 0);

		return Scaffold(
			appBar: AppBar(
				title: const Text('Ruta al destino'),
				backgroundColor: AppColores.primary,
				foregroundColor: Colors.white,
				automaticallyImplyLeading: false,
			),
			body: SafeArea(
				child: Column(
					children: [
						Expanded(
							child: AppGoogleMap(
								initialTarget: initialTarget,
								initialZoom: 15.0,
								onMapCreated: _onMapCreated,
							myLocationEnabled: false,
							myLocationButtonEnabled: false,
								compassEnabled: true,
								markers: markers,
								polylines: _polylines,
							),
						),
						Container(
							width: double.infinity,
							decoration: BoxDecoration(
								color: Colors.white,
								borderRadius: const BorderRadius.only(
									topLeft: Radius.circular(24),
									topRight: Radius.circular(24),
								),
								boxShadow: [
									BoxShadow(
										color: Colors.black.withOpacity(0.08),
										blurRadius: 10,
										offset: const Offset(0, -2),
									),
								],
							),
							padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
							child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Row(
										crossAxisAlignment: CrossAxisAlignment.center,
										mainAxisAlignment: MainAxisAlignment.spaceAround,
										children: [
											// Izquierda: Círculo, nombre y estrellas
											Column(
												mainAxisSize: MainAxisSize.min,
												children: [
													CircleAvatar(
														radius: 35,
														backgroundColor: Colors.grey.shade200,
														backgroundImage: (_conductorFoto != null && _conductorFoto!.isNotEmpty)
																? NetworkImage(_conductorFoto!)
																: null,
														child: (_conductorFoto == null || _conductorFoto!.isEmpty)
																? const Icon(Icons.person, size: 28, color: Colors.black87)
																: null,
													),
													const SizedBox(height: 10),
													Text(
														_conductorNombre ?? 'Conductor',
														style: const TextStyle(
															fontSize: 20,
															fontWeight: FontWeight.w600,
														),
														maxLines: 1,
														overflow: TextOverflow.ellipsis,
													),
													const SizedBox(height: 4),
													StreamBuilder<DocumentSnapshot>(
														stream: _conductorId != null
																? FirebaseFirestore.instance
																		.collection('conductor')
																		.doc(_conductorId)
																		.snapshots()
																: null,
														builder: (context, snapshot) {
															double promedio = 0.0;

															if (snapshot.hasData && snapshot.data!.exists) {
																final data = snapshot.data!.data() as Map<String, dynamic>?;
																if (data != null) {
																	promedio = (data['calificacion_promedio'] as num?)?.toDouble() ?? 0.0;
																}
															}

															final promedioInt = promedio.toInt();
															final tieneMedia = (promedio - promedioInt) >= 0.5;

															return Row(
																mainAxisSize: MainAxisSize.min,
																children: List.generate(5, (index) {
																	if (index < promedioInt) {
																		return const Padding(
																			padding: EdgeInsets.symmetric(horizontal: 1.0),
																			child: Icon(
																				Icons.star,
																				size: 14,
																				color: Colors.amber,
																			),
																		);
																	} else if (index == promedioInt && tieneMedia) {
																		return const Padding(
																			padding: EdgeInsets.symmetric(horizontal: 1.0),
																			child: Icon(
																				Icons.star_half,
																				size: 14,
																				color: Colors.amber,
																			),
																		);
																	} else {
																		return Padding(
																			padding: const EdgeInsets.symmetric(horizontal: 1.0),
																			child: Icon(
																				Icons.star_border,
																				size: 14,
																				color: Colors.grey[400],
																			),
																		);
																	}
																}),
															);
														},
													),
												],
											),
											const SizedBox(width: 24),
											// Derecha: Carrito y placa
											Column(
												mainAxisSize: MainAxisSize.min,
												children: [
													if (_conductorPlaca != null && _conductorPlaca!.isNotEmpty) ...[
														Image.asset(
															'assets/img/carrito.png',
															height: 90,
															fit: BoxFit.contain,
														),
														const SizedBox(height: 4),
														Text(
															_conductorPlaca!,
															style: const TextStyle(
																fontSize: 16,
																fontWeight: FontWeight.w700,
															),
														),
													],
												],
											),
										],
									),
									const SizedBox(height: 16),
									Row(
										children: [
											Expanded(
												child: ElevatedButton(
													onPressed: _showDetalles,
													style: ElevatedButton.styleFrom(
														backgroundColor: AppColores.primary,
														foregroundColor: Colors.white,
														padding: const EdgeInsets.symmetric(vertical: 14),
														shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
													),
													child: const Text('Detalles'),
												),
											),
										],
									),
								],
							),
						),
					],
				),
			),
		);
	}

	Future<void> _openExternalMaps() async {
		try {
			final destino = _destinoLocation;
			if (destino == null) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('No se encuentra la ubicación de destino')),
				);
				return;
			}
			final url = Uri.parse(
				'https://www.google.com/maps/dir/?api=1'
				'&destination=${destino.latitude},${destino.longitude}'
				'&travelmode=driving',
			);

			if (await canLaunchUrl(url)) {
				await launchUrl(url, mode: LaunchMode.externalApplication);
			} else {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('No se pudo abrir Google Maps')),
				);
			}
		} catch (_) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Error al intentar abrir Google Maps')),
			);
		}
	}

	void _showDetalles() {
		showModalBottomSheet(
			context: context,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
			),
			builder: (ctx) {
				return Padding(
					padding: const EdgeInsets.all(16),
					child: Column(
						mainAxisSize: MainAxisSize.min,
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Row(
								children: [
									CircleAvatar(
										radius: 32,
										backgroundColor: Colors.grey.shade200,
										backgroundImage: (_conductorFoto != null && _conductorFoto!.isNotEmpty)
												? NetworkImage(_conductorFoto!)
												: null,
										child: (_conductorFoto == null || _conductorFoto!.isEmpty)
												? const Icon(Icons.person, color: Colors.black87)
												: null,
									),
									const SizedBox(width: 12),
									Expanded(
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													_conductorNombre ?? 'Conductor',
													style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
													maxLines: 1,
													overflow: TextOverflow.ellipsis,
												),
												const SizedBox(height: 4),
												Text(
													_destinoTitulo ?? 'Destino',
													style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
													maxLines: 2,
													overflow: TextOverflow.ellipsis,
												),
												if (_conductorPlaca != null && _conductorPlaca!.isNotEmpty) ...[
													const SizedBox(height: 8),
													Row(
														children: [
															Image.asset(
																'assets/img/carrito.png',
																height: 32,
																fit: BoxFit.contain,
															),
															const SizedBox(width: 8),
															Text(
																_conductorPlaca!,
																style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
															),
														],
													),
												],
											],
										),
									),
								],
							),
							const SizedBox(height: 16),
							SizedBox(
								width: double.infinity,
								child: OutlinedButton.icon(
									onPressed: () {
										Navigator.of(ctx).pop();
										_openExternalMaps();
									},
									icon: const Icon(Icons.navigation_outlined),
									label: const Text('Abrir en Google Maps'),
									style: OutlinedButton.styleFrom(
										foregroundColor: AppColores.primary,
										side: BorderSide(color: AppColores.primary.withOpacity(0.8), width: 1.2),
										padding: const EdgeInsets.symmetric(vertical: 12),
										shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
									),
								),
							),
						],
					),
				);
			},
		);
	}
}
