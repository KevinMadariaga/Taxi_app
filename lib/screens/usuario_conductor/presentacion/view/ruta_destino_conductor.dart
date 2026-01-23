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
import 'package:taxi_app/services/ubicacion_servicio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class RutaDestinoConductorView extends StatefulWidget {
  final String solicitudId;
  final LatLng? destinoLocation;

  const RutaDestinoConductorView({Key? key, required this.solicitudId, this.destinoLocation}) : super(key: key);

  @override
  State<RutaDestinoConductorView> createState() => _RutaDestinoConductorViewState();
}

class _RutaDestinoConductorViewState extends State<RutaDestinoConductorView> {
  GoogleMapController? _mapController;
  LatLng? _driverLocation;
  LatLng? _destinoLocation;
  BitmapDescriptor? _driverIcon;
  BitmapDescriptor? _destinoIcon;
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  int _lastRouteCutIndex = 0;

  late final RutaConductorUsuarioViewModel _vm;
  StreamSubscription<LatLng>? _driverSub;
  StreamSubscription<LatLng>? _locationSub;
  bool _loading = true;
  bool _terminandoDialogoMostrado = false;
  final FirebaseService _firebaseService = FirebaseService();

  String? _clientName;
  String? _clientPhotoUrl;
  String? _destinoDireccion;
  LatLng? _clientLocation;
  String? _clientAddress;

  // Nueva variable para controlar si el botón debe estar habilitado
  bool _puedeTerminarViaje = false;

  @override
  void initState() {
    super.initState();
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
    });
    // Suscribirse al servicio de ubicación local para enviar/actualizar
    // la ubicación en Firestore en cada movimiento del GPS.
    try {
      _locationSub = UbicacionService().listenWithCallback((latlng) async {
        try {
          _driverLocation = latlng;
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await _firebaseService.guardarUbicacionConductor(conductorId: uid, position: latlng);
            await _firebaseService.actualizarUbicacionConductorEnSolicitud(solicitudId: widget.solicitudId, position: latlng);
          }
          // Actualizar ruta o recortar si ya hay una
          if (_driverLocation != null && _destinoLocation != null) {
            if (_routePoints.isEmpty) {
              _fetchRouteOSRM(_driverLocation!, _destinoLocation!);
            } else {
              _shortenRouteToDriver();
            }
            final dist = _haversineDistanceMeters(_driverLocation!, _destinoLocation!);
            final puedeTerminar = dist <= 50;
            if (_puedeTerminarViaje != puedeTerminar) {
              setState(() {
                _puedeTerminarViaje = puedeTerminar;
              });
            }
          }
        } catch (_) {}
        if (mounted) setState(() {});
      }, distanceFilter: 8);
    } catch (_) {}
  }

  Future<void> _loadIcons() async {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

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
      final snap = await FirebaseFirestore.instance.collection('solicitudes').doc(widget.solicitudId).get();
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
              destino = LatLng((lat as num).toDouble(), (lng as num).toDouble());
            }
          }

          final dir = rawDestino['title'] ??
              rawDestino['direccion'] ??
              rawDestino['address'] ??
              rawDestino['direccion_destino'];
          if (dir is String && dir.trim().isNotEmpty) {
            _destinoDireccion = dir.trim();
          }
        }

        // Leer datos del cliente (nombre y foto)
        final rawCliente = data['cliente'];
        if (rawCliente is Map) {
          // intentar leer ubicación del cliente
          final clienteUbic = rawCliente['ubicacion'] ?? rawCliente['location'] ?? rawCliente['locationData'];
          if (clienteUbic is Map) {
            final lat = (clienteUbic['lat'] ?? clienteUbic['latitude'] ?? clienteUbic['latitud']);
            final lng = (clienteUbic['lng'] ?? clienteUbic['longitude'] ?? clienteUbic['longitud']);
            if (lat != null && lng != null) {
              _clientLocation = LatLng((lat as num).toDouble(), (lng as num).toDouble());
            }
            final addr = clienteUbic['address'] ?? clienteUbic['direccion'] ?? clienteUbic['title'];
            if (addr is String && addr.trim().isNotEmpty) _clientAddress = addr.trim();
          }
          final nombre = rawCliente['nombre'] ?? rawCliente['name'];
          final foto = rawCliente['foto'] ?? rawCliente['photo'] ?? rawCliente['photoUrl'] ?? rawCliente['imagen'];
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
        final dist = _haversineDistanceMeters(_driverLocation!, _destinoLocation!);
        final puedeTerminar = dist <= 50;
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
    _driverSub?.cancel();
    try { _vm.dispose(); } catch (_) {}
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
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
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

      // Orientar cámara hacia el destino con zoom dinámico
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

      // Si muy cerca del destino, limpiar la polilínea
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
    // No agregar un Marker rojo para el conductor: usar el punto azul nativo (`myLocationEnabled`) en su lugar.
    // Esto evita que un pin rojo se superponga a la ubicación actual.
    if (_destinoLocation != null) {
      // Only show destino marker if it's not effectively at the same
      // position as the driver (avoid overlapping red marker on driver).
        // Ocultar marcador de destino si está muy cerca del conductor
        // para evitar que el pin rojo quede encima del punto azul (mi ubicación).
        final shouldShowDestino = _driverLocation == null ||
          _haversineDistanceMeters(_driverLocation!, _destinoLocation!) > 35;
      if (shouldShowDestino) {
        markers.add(
          Marker(
            markerId: const MarkerId('destino'),
            position: _destinoLocation!,
            icon: _destinoIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destino'),
          ),
        );
      }
    }

    final initialTarget = _driverLocation ?? _destinoLocation ?? const LatLng(0, 0);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
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
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  compassEnabled: true,
                  markers: markers,
                  polylines: _polylines,
                ),
              ),
              Container(
                width: double.infinity,
                constraints: BoxConstraints(minHeight: ResponsiveHelper.hp(context, 18)),
                margin: EdgeInsets.only(bottom: ResponsiveHelper.hp(context, 1)),
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
                padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 4), vertical: ResponsiveHelper.hp(context, 2)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: ResponsiveHelper.sp(context, 34),
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: (_clientPhotoUrl != null && _clientPhotoUrl!.isNotEmpty)
                              ? NetworkImage(_clientPhotoUrl!)
                              : null,
                          child: (_clientPhotoUrl == null || _clientPhotoUrl!.isEmpty)
                              ? Icon(Icons.person, size: ResponsiveHelper.sp(context, 22), color: Colors.black87)
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
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                              Text(
                                _destinoDireccion ?? 'Destino',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 12),
                                  color: Colors.grey.shade700,
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
                            icon: Icon(Icons.navigation_outlined, size: ResponsiveHelper.sp(context, 16)),
                            label: Text('Maps', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColores.primary,
                              side: BorderSide(color: AppColores.primary.withOpacity(0.8), width: 1.2),
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.wp(context, 3)),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _puedeTerminarViaje ? _terminarViaje : null,
                            icon: Icon(Icons.flag_outlined, size: ResponsiveHelper.sp(context, 16)),
                            label: Text('Terminar viaje', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColores.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _terminarViaje() async {
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
          final fechaAceptacion = data['fecha de aceptacion conductor'] as Timestamp?;
          final completedAt = Timestamp.now();
          
          // Calcular duración en minutos usando los timestamps
          int durationMinutes = 0;
          if (fechaAceptacion != null) {
            durationMinutes = completedAt.toDate().difference(fechaAceptacion.toDate()).inMinutes;
          }
          
          // Guardar fecha de terminación y duración en solicitud
          await FirebaseFirestore.instance
              .collection('solicitudes')
              .doc(widget.solicitudId)
              .update({
                'fecha de terminacion': completedAt,
                'duracion minutos': durationMinutes,
              });

          // Crear registro en historial de viajes
          final clienteData = data['cliente'] as Map<String, dynamic>? ?? {};
          final conductorData = data['conductor'] as Map<String, dynamic>? ?? {};
          final destinoData = data['destino'] as Map<String, dynamic>? ?? {};
          
          // Extraer datos del origen
        
          final addressOrigen = clienteData['ubicacion']?['address'] ?? 'Ubicación inicial';
          
          // Extraer datos del destino
          final addressDestino = destinoData['title'] ?? 'Destino';
          
          // Extraer datos del cliente
          final clienteId = data['clienteId'] ?? clienteData['id'] ?? '';
          final nombreCliente = clienteData['nombre'] ?? 'Cliente';
          
          // Extraer datos del conductor
          final conductorId = data['conductorId'] ?? conductorData['id'] ?? '';
          final nombreConductor = conductorData['nombre'] ?? 'Conductor';
          final placa = conductorData['vehiculo']?['placa'] ?? conductorData['placa'] ?? '';
          
          final tripData = {
            'status': 'completado',
            'createdAt': data['fecha de aceptacion conductor'] ?? Timestamp.now(),
            'completedAt': completedAt,
            'cliente': {
              'id': clienteId,
              'name': nombreCliente,
            },
            'conductor': {
              'id': conductorId,
              'name': nombreConductor,
              'Placa': placa,
            },
            'origen': addressOrigen,
            'destino': addressDestino,
            'distanceKm': data['distanceKm'] ?? 0.0,
            'duracion minutos': durationMinutes,
            'tarifa': {
              'total': data['valor'] ?? 0,
              'currency': 'COP',
            },
            'metodoPago': (data['metodo_pago']?.toString() ?? 'efectivo').toLowerCase(),
            'calificacion': null,
            'solicitudId': widget.solicitudId,
            'timestamp': FieldValue.serverTimestamp(),
          };
          
          // Nota: ya no se crea ni guarda un documento en 'historial viajes'.
          // Se omite la creación del historial y la actualización de
          // 'historial_viaje_id' en la solicitud según la nueva lógica.
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
          builder: (_) => ResumenConductorView(solicitudId: widget.solicitudId),
        ),
        (route) => false,
      );
    });
  }
}
