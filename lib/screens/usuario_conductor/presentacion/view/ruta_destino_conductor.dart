import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/ruta_conductor_viewmodel.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';

class RutaDestinoConductorView extends StatefulWidget {
  final String solicitudId;
  final LatLng? destinoLocation;

  const RutaDestinoConductorView({
    Key? key,
    required this.solicitudId,
    this.destinoLocation,
  }) : super(key: key);

  @override
  State<RutaDestinoConductorView> createState() =>
      _RutaDestinoConductorViewState();
}

class _RutaDestinoConductorViewState extends State<RutaDestinoConductorView>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  LatLng? _driverLocation;
  LatLng? _destinoLocation;
  BitmapDescriptor? _destinoIcon;
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  int _lastRouteCutIndex = 0;

  late final RutaConductorUsuarioViewModel _vm;
  StreamSubscription<LatLng>? _driverSub;
  StreamSubscription<LatLng>? _locationSub;
  bool _loading = true;
  bool _terminandoDialogoMostrado = false;
  // Mostrar loader centrado en el mapa mientras se obtiene la ruta/dirección
  bool _obteniendoDireccion = false;
  final FirebaseService _firebaseService = FirebaseService();

  String? _clientName;
  String? _clientPhotoUrl;
  String? _destinoDireccion;

  // Nueva variable para controlar si el botón debe estar habilitado
  bool _puedeTerminarViaje = false;
  // Distancia actual al destino en metros y duración estimada de la ruta en minutos
  double? _distanceToDestinationMeters;
  int? _routeDurationMin;
  bool _initializing = true;
  bool _initializationScheduled = false;
  late DateTime _initStart;
  bool _firstEntryNotificationShown = false;

  @override
  void initState() {
    super.initState();
    _initStart = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _vm = RutaConductorUsuarioViewModel(solicitudId: widget.solicitudId);
    _destinoLocation = widget.destinoLocation;
    _loadIcons();
    _ensureDestino();
    _subscribeDriver();
    // Inicializar ViewModel después del primer frame para arrancar tracking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _vm.init(context);
      } catch (_) {}
      // Notificación solo la primera vez que se entra a esta vista
      try {
        _showFirstEntryNotification();
      } catch (_) {}
      _iniciarTrackingConSegundoPlano();
    });
  }

  Future<void> _iniciarTrackingConSegundoPlano() async {
    try {
      await TrackingService().iniciarEscuchaGPS(
        distanceFilter: 10,
        timeInterval: 10,
        onLocationUpdate: (position) async {
          final latlng = LatLng(position.latitude, position.longitude);
          _driverLocation = latlng;
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await _firebaseService.guardarUbicacionConductor(
              conductorId: uid,
              position: latlng,
            );
            await _firebaseService.actualizarUbicacionConductorEnSolicitud(
              solicitudId: widget.solicitudId,
              position: latlng,
            );
          }
          // Actualizar ruta o recortar si ya hay una
          if (_driverLocation != null && _destinoLocation != null) {
            if (_routePoints.isEmpty) {
              _fetchRouteOSRM(_driverLocation!, _destinoLocation!);
            } else {
              _shortenRouteToDriver();
            }
            final dist = _haversineDistanceMeters(
              _driverLocation!,
              _destinoLocation!,
            );
            _distanceToDestinationMeters = dist;
            final puedeTerminar = dist <= 70;
            if (_puedeTerminarViaje != puedeTerminar) {
              setState(() {
                _puedeTerminarViaje = puedeTerminar;
              });
            }
          }
          if (mounted) setState(() {});
        },
      );
    } catch (_) {}

  }

  void _maybeCompleteInitialization() {
    if (!_initializing || _initializationScheduled) return;
    if (_loading || _destinoLocation == null) return;

    const minDuration = Duration(seconds: 3);
    final elapsed = DateTime.now().difference(_initStart);
    final remaining = elapsed >= minDuration
        ? Duration.zero
        : minDuration - elapsed;

    _initializationScheduled = true;
    Future.delayed(remaining, () {
      if (!mounted) return;
      setState(() {
        _initializing = false;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Cuando la app se reanuda y esta vista está montada, mostrar notificación
      try {
        _showContinueNotification();
      } catch (_) {}
    }
  }

  void _showFirstEntryNotification() {
    if (_firstEntryNotificationShown) return;
    _firstEntryNotificationShown = true;
    try {
      NotificacionesServicio.instance.showTripNotification(
        title: 'Continúa hacia el destino',
        body: 'Lleva el cliente a su destino.',
      );
    } catch (_) {}
  }

  void _showContinueNotification() {
    try {
      NotificacionesServicio.instance.showTripNotification(
        title: 'Continúa el viaje',
        body: 'Lleva el cliente a su destino.',
      );
    } catch (_) {}
  }

  Future<void> _loadIcons() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;

      final destino = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() {
        _destinoIcon = destino;
      });
    } catch (_) {}
  }

  Future<void> _ensureDestino() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .get();
      final data = snap.data();
      if (data != null) {
        LatLng? destino;
        final rawDestino = data['destino'] ?? data['destination'];
        if (rawDestino is Map) {
          final u = (rawDestino['ubicacion'] ?? rawDestino);
          if (u is Map) {
            final lat = (u['lat'] ?? u['latitude'] ?? u['latitud']);
            final lng = (u['lng'] ?? u['longitude'] ?? u['longitud']);
            if (lat != null && lng != null) {
              destino = LatLng(
                (lat as num).toDouble(),
                (lng as num).toDouble(),
              );
            }
          }

          final dir =
              rawDestino['direccion'] ??
              rawDestino['address'] ??
              rawDestino['direccion_destino'] ??
              rawDestino['title'];
          if (dir is String && dir.trim().isNotEmpty) {
            _destinoDireccion = dir.trim();
          }
        }

        // Leer datos del cliente (nombre y foto)
        final rawCliente = data['cliente'];
        if (rawCliente is Map) {
          // intentar leer ubicación del cliente
          final clienteUbic =
              rawCliente['ubicacion'] ??
              rawCliente['location'] ??
              rawCliente['locationData'];
          if (clienteUbic is Map) {
            // Datos de ubicación del cliente ya no se usan de forma directa aquí.
          }
          final nombre = rawCliente['nombre'] ?? rawCliente['name'];
          final foto =
              rawCliente['foto'] ??
              rawCliente['photo'] ??
              rawCliente['photoUrl'] ??
              rawCliente['imagen'];
          if (nombre is String) {
            _clientName = nombre.trim();
          }
          if (foto is String) {
            _clientPhotoUrl = foto.trim();
          } else if (foto is Map) {
            final url = foto['url'] ?? foto['link'];
            if (url is String) _clientPhotoUrl = url.trim();
          }
        }
        if (destino != null && _destinoLocation == null) {
          setState(() => _destinoLocation = destino);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _subscribeDriver() {
    _driverSub?.cancel();
    _driverSub = _vm.listenPosicionConductor().listen((pos) {
      _driverLocation = pos;
      if (_driverLocation != null && _destinoLocation != null) {
        if (_routePoints.isEmpty) {
          _fetchRouteOSRM(_driverLocation!, _destinoLocation!);
        } else {
          _shortenRouteToDriver();
        }
        // Verificar si está a 50 metros o menos del destino
            final dist = _haversineDistanceMeters(
              _driverLocation!,
              _destinoLocation!,
            );
            _distanceToDestinationMeters = dist;
            final puedeTerminar = dist <= 70;
        if (_puedeTerminarViaje != puedeTerminar) {
          setState(() {
            _puedeTerminarViaje = puedeTerminar;
          });
        }
      }
      setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driverSub?.cancel();
    try {
      _vm.dispose();
    } catch (_) {}
    _locationSub?.cancel();
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
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
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
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }

  Future<void> _fetchRouteOSRM(LatLng origin, LatLng dest) async {
    setState(() => _obteniendoDireccion = true);
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
      final durationSec = (route0['duration'] as num?)?.toDouble();
      final durationMin = durationSec != null ? (durationSec / 60.0) : null;
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
        if (durationMin != null) {
          _routeDurationMin = durationMin.round();
        } else {
          _routeDurationMin = null;
        }
        _obteniendoDireccion = false;
      });

      // Orientar cámara desde la posición del conductor hacia el destino,
      // con perspectiva de viaje (bearing y zoom dinámico).
      if (_mapController != null && points.isNotEmpty) {
        try {
          final bearing = _calculateBearing(origin, dest);
          final dist = _haversineDistanceMeters(origin, dest);
          final zoom = _zoomForDistanceMeters(dist);
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: origin, zoom: zoom, bearing: bearing),
            ),
          );
        } catch (_) {}
      }
    } catch (_) {
      // fallthrough
    } finally {
      if (mounted && _obteniendoDireccion)
        setState(() => _obteniendoDireccion = false);
    }
  }

  void _shortenRouteToDriver() {
    try {
      if (_routePoints.isEmpty || _driverLocation == null) return;

      // Si muy cerca del destino, limpiar la polilínea
      final dest = _destinoLocation;
      if (dest != null) {
        final distToDest = _haversineDistanceMeters(_driverLocation!, dest);
        if (distToDest < 35) {
          setState(() {
            _routePoints = [];
            _polylines = _polylines
                .where((p) => p.polylineId.value != 'route')
                .toSet();
          });
          return;
        }
      }

      // Buscar el punto de ruta más cercano al conductor
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

      // Orientar cámara hacia el siguiente punto con zoom dinámico
      if (_mapController != null && _routePoints.length >= 2) {
        final nextPoint = _routePoints[1];
        final bearing = _calculateBearing(_driverLocation!, nextPoint);
        final dist = _haversineDistanceMeters(_driverLocation!, nextPoint);
        final zoom = _zoomForDistanceMeters(dist);
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _driverLocation!,
              zoom: zoom,
              bearing: bearing,
              tilt: 45,
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _maybeCompleteInitialization();

    if (_initializing || _loading) {
      return const Scaffold(
        backgroundColor: AppColores.background,
        body: SafeArea(
          child: Center(
            child: MapLoadingWidget(message: 'Preparando ruta al destino...'),
          ),
        ),
      );
    }

    final markers = <Marker>{};
    // Mostrar siempre el marcador rojo del destino cuando haya coordenadas.
    if (_destinoLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destino'),
          position: _destinoLocation!,
          icon:
              _destinoIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      );
    }

    final initialTarget =
        _driverLocation ?? _destinoLocation ?? const LatLng(0, 0);

    // Distancia formateada: si sería "0.0 km", mostrar en metros
    final String? distanceText;
    if (_distanceToDestinationMeters != null) {
      final meters = _distanceToDestinationMeters!;
      final dKm = meters / 1000.0;
      if (dKm < 0.1) {
        // Menos de 100 m, mostrar en metros
        distanceText = '${meters.toStringAsFixed(0)} m';
      } else {
        distanceText = '${dKm.toStringAsFixed(1)} km';
      }
    } else {
      distanceText = null;
    }

    // Tiempo estimado: en minutos si es < 60, si no en horas y minutos
    final String? etaText;
    if (_routeDurationMin != null) {
      final totalMin = _routeDurationMin!;
      if (totalMin < 60) {
        etaText = 'Aprox. $totalMin min';
      } else {
        final horas = totalMin ~/ 60;
        final minutosRestantes = totalMin % 60;
        if (minutosRestantes == 0) {
          etaText = 'Aprox. ${horas} h';
        } else {
          etaText = 'Aprox. ${horas} h ${minutosRestantes} min';
        }
      }
    } else {
      etaText = null;
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ruta al destino'),
          backgroundColor: AppColores.primary,
          foregroundColor: AppColores.textWhite,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    AppGoogleMap(
                      initialTarget: initialTarget,
                      initialZoom: 15.0,
                      onMapCreated: _onMapCreated,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      compassEnabled: true,
                      markers: markers,
                      polylines: _polylines,
                    ),
                    // Botón flotante de seguridad debajo del botón de centrar mapa
                    Positioned(
                      right: ResponsiveHelper.wp(context, 4),
                      top: ResponsiveHelper.hp(context, 8),
                      child: SafeArea(
                        child: FloatingActionButton(
                          heroTag: 'safetyFabConductor',
                          backgroundColor: AppColores.surface,
                          foregroundColor: AppColores.textPrimary,
                          onPressed: _showSafetySheet,
                          child: const Icon(Icons.shield_outlined),
                        ),
                      ),
                    ),
                    if (distanceText != null)
                      Positioned(
                        bottom: ResponsiveHelper.hp(context, 1.2),
                        left: ResponsiveHelper.wp(context, 4),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.wp(context, 3.2),
                            vertical: ResponsiveHelper.hp(context, 0.6),
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColores.cardBackground.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColores.borderSubtle,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: ResponsiveHelper.sp(context, 14),
                                color: AppColores.primary,
                              ),
                              SizedBox(
                                width: ResponsiveHelper.wp(context, 1.2),
                              ),
                              Text(
                                distanceText,
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 12),
                                  color: AppColores.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (etaText != null)
                      Positioned(
                        bottom: ResponsiveHelper.hp(context, 1.2),
                        right: ResponsiveHelper.wp(context, 4),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.wp(context, 3.2),
                            vertical: ResponsiveHelper.hp(context, 0.6),
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColores.cardBackground.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColores.borderSubtle,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: ResponsiveHelper.sp(context, 14),
                                color: AppColores.primary,
                              ),
                              SizedBox(
                                width: ResponsiveHelper.wp(context, 1.2),
                              ),
                              Text(
                                etaText,
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 12),
                                  color: AppColores.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_obteniendoDireccion)
                      Positioned.fill(
                        child: Container(
                          color: AppColores.overlayLight,
                          child: const Center(
                            child: MapLoadingWidget(
                              message: 'Obteniendo dirección...',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  minHeight: ResponsiveHelper.hp(context, 22),
                ),
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: AppColores.sheetBackground,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColores.borderSubtle,
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.wp(context, 4),
                  ResponsiveHelper.hp(context, 2.2),
                  ResponsiveHelper.wp(context, 4),
                  ResponsiveHelper.hp(context, 2.4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: ResponsiveHelper.sp(context, 34),
                          backgroundColor: AppColores.grey200,
                          backgroundImage:
                              (_clientPhotoUrl != null &&
                                  _clientPhotoUrl!.isNotEmpty)
                              ? NetworkImage(_clientPhotoUrl!)
                              : null,
                          child:
                              (_clientPhotoUrl == null ||
                                  _clientPhotoUrl!.isEmpty)
                              ? Icon(
                                  Icons.person,
                                  size: ResponsiveHelper.sp(context, 22),
                                  color: AppColores.textPrimary,
                                )
                              : null,
                        ),
                        SizedBox(width: ResponsiveHelper.wp(context, 3)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _clientName ?? 'Cliente',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 16),
                                  fontWeight: FontWeight.w600,
                                  color: AppColores.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(
                                height: ResponsiveHelper.hp(context, 0.6),
                              ),
                              Text(
                                _destinoDireccion ?? 'Destino',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 12),
                                  color: AppColores.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.hp(context, 2)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openExternalMaps,
                            icon: Icon(
                              Icons.navigation_outlined,
                              size: ResponsiveHelper.sp(context, 16),
                            ),
                            label: Text(
                              'Mapa',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.sp(context, 14),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColores.primary,
                              side: BorderSide(
                                color: AppColores.primary.withOpacity(0.8),
                                width: 1.2,
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.hp(context, 1.2),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.wp(context, 3)),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _puedeTerminarViaje
                                ? _terminarViaje
                                : null,
                            icon: Icon(
                              Icons.flag_outlined,
                              size: ResponsiveHelper.sp(context, 16),
                            ),
                            label: Text(
                              'Terminar viaje',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.sp(context, 14),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColores.primary,
                              foregroundColor: AppColores.textWhite,
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.hp(context, 1.2),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
      ),
    );
  }

  void _showSafetySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              media.viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(media.size.height * 0.6, 420),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Herramientas de seguridad',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Usa estas herramientas si te sientes inseguro durante tu viaje.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.headset_mic_outlined,
                        color: AppColores.textPrimary,
                      ),
                      title: Text(
                        'Habla con un agente de seguridad',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Un agente te llamará y te dará orientación durante tu viaje.',
                        style: TextStyle(fontSize: 13),
                      ),
                      trailing: Icon(Icons.chevron_right),
                    ),
                    Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.report_problem_outlined,
                        color: AppColores.textPrimary,
                      ),
                      title: Text(
                        'Reportar un problema de seguridad',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Avísanos si sentiste inseguridad en cualquier momento.',
                        style: TextStyle(fontSize: 13),
                      ),
                      trailing: Icon(Icons.chevron_right),
                    ),
                    Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: AppColores.textPrimary,
                      ),
                      title: Text(
                        'Comparte tu ubicación',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Elige contactos de confianza para compartir tu ubicación.',
                        style: TextStyle(fontSize: 13),
                      ),
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openExternalMaps() async {
    try {
      final destino = _destinoLocation;
      if (destino == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encuentra la ubicación de destino'),
          ),
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

  Future<void> _terminarViaje() async {
    if (_terminandoDialogoMostrado) return; // Solo permitir una acción
    try {
      await _firebaseService.finalizarViaje(widget.solicitudId);
      if (!mounted) return;
      // Obtener la solicitud para calcular duración y crear historial
      try {
        final solicitudSnap = await FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(widget.solicitudId)
            .get();
        final data = solicitudSnap.data();
        if (data != null) {
          final fechaAceptacion =
              data['fecha de aceptacion conductor'] as Timestamp?;
          final completedAt = Timestamp.now();
          int durationMinutes = 0;
          if (fechaAceptacion != null) {
            durationMinutes = completedAt
                .toDate()
                .difference(fechaAceptacion.toDate())
                .inMinutes;
          }
          await FirebaseFirestore.instance
              .collection('solicitudes')
              .doc(widget.solicitudId)
              .update({
                'fecha de terminacion': completedAt,
                'duracion minutos': durationMinutes,
              });
        }
      } catch (e) {
        debugPrint('Error al crear historial: $e');
      }
      _mostrarViajeTerminado();
    } catch (e) {
      debugPrint('Error al terminar viaje: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo finalizar el viaje')),
      );
    }
  }

  void _mostrarViajeTerminado() {
    if (_terminandoDialogoMostrado) return;
    _terminandoDialogoMostrado = true;
    // limpiar cache de la solicitud antes de mostrar el diálogo
    try {
      RouteCacheService.clearSolicitud(widget.solicitudId);
    } catch (_) {}

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
                    color: AppColores.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColores.borderSubtle,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColores.primary,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Viaje Terminado',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColores.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por favor espere...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColores.textSecondary,
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
          builder: (_) => ResumenConductorView(solicitudId: widget.solicitudId),
        ),
        (route) => false,
      );
    });
  }
}
