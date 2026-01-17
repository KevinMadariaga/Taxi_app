import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/map_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/map_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';

class RutaClienteViewModel extends ChangeNotifier {
  final String solicitudId;
  final String? conductorId;
  final String? conductorName;
  final String? conductorPhone;

  RutaClienteViewModel({
    required this.solicitudId,
    this.conductorId,
    this.conductorName,
    this.conductorPhone,
  });

  // --- Estado expuesto a la vista ---

  bool loading = true;

  /// Centro inicial del mapa
  LatLng initialTarget = const LatLng(8.2595534, -73.353469);

  /// Zoom inicial sugerido
  double zoom = 15.0;

  /// Bearing inicial (orientación de la cámara)
  double? initialBearing;

  /// Marcadores para cliente y conductor
  Set<Marker> markers = {};

  /// Polilíneas de la ruta (por ejemplo, cliente-conductor)
  Set<Polyline> polylines = {};

  /// Distancia aproximada de la ruta en km (si OSRM lo devuelve)
  double? routeDistanceKm;

  /// Duración aproximada de la ruta en minutos (si OSRM lo devuelve)
  double? routeDurationMin;

  /// Datos del conductor para el encabezado
  String? conductorPhotoUrl;
  double? conductorRating;
  String? conductorDisplayName;
  String? conductorPlate;

  /// Indicador de nuevo mensaje de chat cuando el sheet está cerrado
  bool hasNewChat = false;

  /// Estado para que la vista pueda reaccionar a cancelaciones remotas
  bool cancelStatusHandled = false;

  /// Indicador para que la vista navegue a la pantalla de destino cuando el estado sea "en camino".
  bool goToDestino = false;

  // --- Dependencias internas ---

  final ChatService _chatService = ChatService();
  final MapService _mapService = const MapService();
  final FirebaseService _firebaseService = FirebaseService();

  StreamSubscription<DocumentSnapshot>? _solicitudSub;
  bool _routeCacheSaved = false;
  StreamSubscription<List<ChatMessage>>? _chatSub;

  /// Bounds actuales del mapa calculados a partir de marcadores y polilíneas.
  ///
  /// Se calcula aquí para que la vista no tenga que usar directamente
  /// `MapService` ni conocer la lógica de cómputo de bounds.
  LatLngBounds? get cameraBounds {
    final points = <LatLng>[];
    for (final m in markers) {
      points.add(m.position);
    }
    for (final poly in polylines) {
      points.addAll(poly.points);
    }
    if (points.isEmpty) return null;
    return _mapService.computeBoundsFromPoints(points);
  }

  // --- Ciclo de vida ---

  Future<void> init() async {
    await _loadSolicitud();
    _subscribeSolicitud();
    _listenChatMessages();
  }

  @override
  void dispose() {
    _solicitudSub?.cancel();
    _chatSub?.cancel();
    super.dispose();
  }

  // --- Carga inicial de la solicitud ---

  Future<void> _loadSolicitud() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();

      final data = doc.data();
      if (data == null) {
        loading = false;
        notifyListeners();
        return;
      }

      LatLng? origen;
      LatLng? conductorPos;

      // origen (cliente): preferir siempre cliente.ubicacion; fallback a 'ubicacion_inicial' o 'origen'
      final rawCliente = data['cliente'];
      if (rawCliente is Map && rawCliente['ubicacion'] is Map) {
        final cu = Map<String, dynamic>.from(rawCliente['ubicacion']);
        final lat = (cu['lat'] ?? cu['latitude'] ?? cu['latitud']);
        final lng = (cu['lng'] ?? cu['longitude'] ?? cu['longitud']);
        if (lat != null && lng != null) {
          origen = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
      }

      // ubicación del conductor desde el objeto 'conductor' en la solicitud
      final rawConductor = data['conductor'];
      if (rawConductor is Map) {
        final lat = (rawConductor['lat'] ??
            rawConductor['latitude'] ??
            rawConductor['latitud']);
        final lng = (rawConductor['lng'] ??
            rawConductor['longitude'] ??
            rawConductor['longitud']);
        if (lat != null && lng != null) {
          conductorPos =
              LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
      }

      final newMarkers = <Marker>{};

      // marcador de la ubicación del cliente
      if (origen != null) {
        newMarkers.add(Marker(
          markerId: const MarkerId('cliente'),
          position: origen,
          infoWindow: const InfoWindow(title: 'Cliente'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ));
      }

      // marcador de la ubicación del conductor
      if (conductorPos != null) {
        newMarkers.add(Marker(
          markerId: const MarkerId('conductor'),
          position: conductorPos,
          infoWindow: const InfoWindow(title: 'Conductor'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ));
      }

      // Trazabilidad (ruta por calles) entre cliente y conductor
      if (origen != null && conductorPos != null) {
        await _fetchRouteOSRM(origen, conductorPos, 'cliente_conductor');
      }

      // Priorizar siempre la ubicación del cliente como centro inicial
      LatLng center = initialTarget;
      if (origen != null) {
        center = origen;
        // Calcular bearing desde cliente hacia conductor para orientar la cámara
        if (conductorPos != null) {
          initialBearing = _calculateBearing(origen, conductorPos);
        }
      } else if (conductorPos != null) {
        center = conductorPos;
      }

      // Datos del conductor
      final resolvedConductorId = conductorId ??
          (data['conductor'] is Map
                  ? (data['conductor']['id'] ??
                      data['conductorId'] ??
                      data['driverId'])
                  : (data['conductorId'] ?? data['driverId']))
              ?.toString();

      if (resolvedConductorId != null && resolvedConductorId.isNotEmpty) {
        try {
          final cdoc = await FirebaseFirestore.instance
              .collection('conductor')
              .doc(resolvedConductorId)
              .get();
          final cdata = cdoc.data();
          if (cdata != null) {
            conductorPhotoUrl = cdata['foto']?.toString();
            conductorRating = (cdata['rating'] is num)
                ? (cdata['rating'] as num).toDouble()
                : null;
            conductorDisplayName =
                cdata['nombre']?.toString() ?? conductorName;
            conductorPlate = cdata['placa']?.toString();
            // Si tenemos datos del conductor, persistir cache para restaurar UI
            try {
              if (!_routeCacheSaved) {
                await RouteCacheService.saveForSolicitud(RouteCacheData(
                  solicitudId: solicitudId,
                  role: 'cliente',
                  conductorId: resolvedConductorId,
                  conductorName: conductorDisplayName,
                  conductorPhone: null,
                  conductorPlate: conductorPlate,
                  conductorPhotoUrl: conductorPhotoUrl,
                  conductorRating: conductorRating,
                ));
                _routeCacheSaved = true;
              }
            } catch (_) {}
          }
        } catch (_) {
          conductorDisplayName = conductorName;
        }
      } else {
        conductorDisplayName = conductorName;
      }

      markers = newMarkers;
      initialTarget = center;
      loading = false;
      notifyListeners();
    } catch (e) {
      loading = false;
      notifyListeners();
    }
  }

  // --- Suscripción en tiempo real a la solicitud ---

  void _subscribeSolicitud() {
    _solicitudSub?.cancel();
    _solicitudSub = FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((doc) async {
      try {
        if (!doc.exists) return;
        final data = doc.data();
        if (data == null) return;

        LatLng? origen;
        LatLng? conductorPos;

        final rawCliente = data['cliente'];
        if (rawCliente is Map && rawCliente['ubicacion'] is Map) {
          final cu = Map<String, dynamic>.from(rawCliente['ubicacion']);
          final lat = (cu['lat'] ?? cu['latitude'] ?? cu['latitud']);
          final lng = (cu['lng'] ?? cu['longitude'] ?? cu['longitud']);
          if (lat != null && lng != null) {
            origen =
                LatLng((lat as num).toDouble(), (lng as num).toDouble());
          }
        }

        final rawConductor = data['conductor'];
        if (rawConductor is Map) {
          final lat = (rawConductor['lat'] ??
              rawConductor['latitude'] ??
              rawConductor['latitud']);
          final lng = (rawConductor['lng'] ??
              rawConductor['longitude'] ??
              rawConductor['longitud']);
          if (lat != null && lng != null) {
            conductorPos = LatLng(
              (lat as num).toDouble(),
              (lng as num).toDouble(),
            );
          }
        }

        final newMarkers = <Marker>{};

        if (origen != null) {
          newMarkers.add(Marker(
            markerId: const MarkerId('cliente'),
            position: origen,
            infoWindow: const InfoWindow(title: 'Cliente'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ));
        }

        if (conductorPos != null) {
          newMarkers.add(Marker(
            markerId: const MarkerId('conductor'),
            position: conductorPos,
            infoWindow: const InfoWindow(title: 'Conductor'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ));
        }

        if (origen != null && conductorPos != null) {
          await _fetchRouteOSRM(origen, conductorPos, 'cliente_conductor');
        }

        // Priorizar siempre la ubicación del cliente como centro
        LatLng center = initialTarget;
        if (origen != null) {
          center = origen;
          // Calcular bearing desde cliente hacia conductor para orientar la cámara
          if (conductorPos != null) {
            initialBearing = _calculateBearing(origen, conductorPos);
          }
        } else if (conductorPos != null) {
          center = conductorPos;
        }

        final estado =
            (data['status'] ?? data['estado'] ?? '').toString().toLowerCase();

        markers = newMarkers;
        initialTarget = center;
        loading = false;

        // actualizar info de conductor si está presente, preferir objeto
        conductorDisplayName = (data['conductor'] is Map
                    ? (data['conductor']['nombre'] ??
                        data['conductorName'] ??
                        data['conductor_name'])
                    : (data['conductorName'] ?? data['conductor_name']))
                ?.toString() ??
            conductorDisplayName;

        // intentar obtener foto/placa/rating del objeto 'conductor' si viene embebido
        try {
          if (data['conductor'] is Map) {
            final cmap = Map<String, dynamic>.from(data['conductor'] as Map);
            conductorPhotoUrl = (cmap['foto'] ?? cmap['fotoUrl'] ?? cmap['photo'])?.toString() ?? conductorPhotoUrl;
            conductorPlate = (cmap['placa'] ?? cmap['plate'])?.toString() ?? conductorPlate;
            conductorRating = (cmap['calificacion_promedio'] is num) ? (cmap['calificacion_promedio'] as num).toDouble() : conductorRating;
          } else {
            // si no viene embebido, intentar resolver por id
            final resolvedConductorId = conductorId ??
                (data['conductor'] is Map
                        ? (data['conductor']['id'] ?? data['conductorId'] ?? data['driverId'])
                        : (data['conductorId'] ?? data['driverId']))
                    ?.toString();
            if (resolvedConductorId != null && resolvedConductorId.isNotEmpty) {
              try {
                final cdoc = await FirebaseFirestore.instance.collection('conductor').doc(resolvedConductorId).get();
                final cdata = cdoc.data();
                if (cdata != null) {
                  conductorPhotoUrl = cdata['foto']?.toString() ?? conductorPhotoUrl;
                  conductorPlate = cdata['placa']?.toString() ?? conductorPlate;
                  conductorRating = (cdata['rating'] is num) ? (cdata['rating'] as num).toDouble() : conductorRating;
                  conductorDisplayName = cdata['nombre']?.toString() ?? conductorDisplayName;
                }
              } catch (_) {}
            }
          }
        } catch (_) {}

        // persistir solicitud activa en cache/shared si está asignada
        try {
          if (estado == 'asignado' || estado == 'assigned') {
            SessionHelper.setActiveSolicitud(solicitudId);
            // guardar en RouteCache si tenemos conductor
            try {
              if (!_routeCacheSaved) {
                await RouteCacheService.saveForSolicitud(RouteCacheData(
                  solicitudId: solicitudId,
                  role: 'cliente',
                  conductorId: (data['conductor'] is Map ? (data['conductor']['id'] ?? data['conductorId'])?.toString() : (data['conductorId'] ?? data['driverId'])?.toString()),
                  conductorName: conductorDisplayName,
                  conductorPhone: null,
                  conductorPlate: conductorPlate,
                  conductorPhotoUrl: conductorPhotoUrl,
                  conductorRating: conductorRating,
                ));
                _routeCacheSaved = true;
              }
            } catch (_) {}
          } else if (estado == 'cancelado' ||
              estado == 'cancelada' ||
              estado == 'finalizado' ||
              estado == 'completed') {
            SessionHelper.clearActiveSolicitud();
            try { await RouteCacheService.clearSolicitud(solicitudId); } catch (_) {}
            _routeCacheSaved = false;
          }
        } catch (_) {}

        // Notificar a la vista que la solicitud fue cancelada remotamente
        if (!cancelStatusHandled &&
            (estado == 'cancelado' || estado == 'cancelada')) {
          cancelStatusHandled = true;
        }

        // Señalar a la vista que debe ir a la pantalla de destino cuando el viaje está en camino
        if (!goToDestino &&
            (estado == 'en camino' || estado == 'en_camino' || estado == 'encamino' || estado == 'en_progreso')) {
          goToDestino = true;
        }

        notifyListeners();
      } catch (_) {}
    });
  }

  /// La vista consume el disparo de navegación a destino para no re-navegar.
  void consumeGoToDestino() {
    goToDestino = false;
  }

  // --- Cancelar solicitud desde la ruta ---

  Future<bool> cancelSolicitudFromRoute() async {
    try {
      await _firebaseService.cancelarViaje(
        solicitudId: solicitudId,
        canceladoPor: 'cliente',
      );
      try {
        SessionHelper.clearActiveSolicitud();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Chat: escucha de mensajes para indicador de nuevo mensaje ---

  void _listenChatMessages() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chatSub?.cancel();
    _chatSub = _chatService.listenMessages(solicitudId).listen(
      (mensajes) {
        if (mensajes.isEmpty) return;
        final last = mensajes.last;
        final esDeOtro = last.senderId != uid;
        if (esDeOtro) {
          hasNewChat = true;
          final texto = last.texto.trim();
          if (texto.isNotEmpty) {
            NotificacionesServicio.instance.showChatNotification(
              senderName: 'Conductor',
              message: texto,
            );
          }
          notifyListeners();
        }
      },
      onError: (_) {},
    );
  }

  /// Permite que la vista "consuma" el indicador de nuevo chat
  void clearNewChatFlag() {
    if (!hasNewChat) return;
    hasNewChat = false;
    notifyListeners();
  }

  // --- OSRM: cálculo de ruta y métricas ---

  Future<void> _fetchRouteOSRM(
      LatLng origin, LatLng dest, String polyId) async {
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson');
      final resp =
          await http.get(url).timeout(const Duration(seconds: 6));
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

      final newPolylines = Set<Polyline>.from(polylines);
      newPolylines.removeWhere((p) => p.polylineId.value == polyId);
      final color = polyId == 'route'
          ? const Color.fromARGB(255, 211, 162, 0)
          : Colores.amarillo;
      newPolylines.add(_mapService.createPolyline(
        id: polyId,
        points: points,
        color: color,
        width: 5,
        geodesic: true,
      ));
      polylines = newPolylines;

      final distance = (route0['distance'] is num)
          ? (route0['distance'] as num).toDouble()
          : null;
      final duration = (route0['duration'] is num)
          ? (route0['duration'] as num).toDouble()
          : null;
      if (distance != null) {
        routeDistanceKm = distance / 1000.0;
      } else {
        // Fallback: calcular distancia aproximada desde los puntos
        final dMeters = MapHelper.routeDistanceMeters(points);
        routeDistanceKm = dMeters / 1000.0;
      }
      if (duration != null) {
        routeDurationMin = duration / 60.0;
      }

      notifyListeners();
    } catch (_) {
      // ignorar silenciosamente
    }
  }

  /// Calcula el bearing (dirección) desde un punto origen hacia un destino
  /// en grados (0-360), donde 0 es Norte
  double _calculateBearing(LatLng from, LatLng to) {
    final fromLat = from.latitude * (3.141592653589793 / 180.0);
    final fromLng = from.longitude * (3.141592653589793 / 180.0);
    final toLat = to.latitude * (3.141592653589793 / 180.0);
    final toLng = to.longitude * (3.141592653589793 / 180.0);

    final dLng = toLng - fromLng;
    final y = sin(dLng) * cos(toLat);
    final x = cos(fromLat) * sin(toLat) - sin(fromLat) * cos(toLat) * cos(dLng);
    
    final bearing = atan2(y, x);
    return (bearing * (180.0 / 3.141592653589793) + 360) % 360;
  }
}
