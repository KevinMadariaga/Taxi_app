import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/ruta_destino_conductor.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/ruta_conductor_viewmodel.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';

class RutaConductorView extends StatefulWidget {
  final String solicitudId;
  final LatLng? clientLocation;
  final String? clientName;
  final String? clientAddress;
  final LatLng? driverLocation;
  final VoidCallback? onChat;
  final VoidCallback? onArrived;
  final VoidCallback? onDetails;

  const RutaConductorView({
    Key? key,
    required this.solicitudId,
    this.clientLocation,
    this.clientName,
    this.clientAddress,
    this.driverLocation,
    this.onChat,
    this.onArrived,
    this.onDetails,
  }) : super(key: key);

  @override
  State<RutaConductorView> createState() => _RutaConductorViewState();
}

class _RutaConductorViewState extends State<RutaConductorView> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  BitmapDescriptor? _clientMarkerIcon;
  LatLng? _clientLocation;
  LatLng? _driverLocation;
  String? _clientName;
  String? _clientAddress;
  String? _clientPhotoUrl;
  int? _routeDurationMin;
  bool _loadingSolicitud = false;
  final ChatService _chatService = ChatService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  StreamSubscription<List<ChatMessage>>? _chatSub;
  StreamSubscription<LatLng>? _driverPosSub;
  bool _hasNewChat = false;
  bool _isChatOpen = false;
  late final RutaConductorUsuarioViewModel _viewModel;
  int _lastRouteCutIndex = 0;
  RouteCacheData? _routeCache;
  bool _cachePersistedConductor = false;

  @override
  void initState() {
    super.initState();
    _viewModel = RutaConductorUsuarioViewModel(
      solicitudId: widget.solicitudId,
      onSolicitudCancelada: _handleSolicitudCancelada,
      notificacionesServicio: NotificacionesServicio.instance,
    );

    _loadClientMarkerIcon();
    _restoreCacheAndNotifyConductor();
    _initFromSolicitud();
    _listenChatMessages();
    _driverPosSub = _viewModel.listenPosicionConductor().listen((pos) {
      if (!mounted) return;
      setState(() {
        _driverLocation = pos;
      });
      // Acortar ruta si ya existe, y si no hay ruta dibujada intentar obtenerla
      _shortenRouteToDriver();
      _maybeFetchRouteIfNeeded();
    }, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.init(context);
    });
  }

  Future<void> _restoreCacheAndNotifyConductor() async {
    try {
      final cache = await RouteCacheService.loadForSolicitud(widget.solicitudId);
      if (!mounted) return;
      if (cache != null) {
        setState(() {
          _routeCache = cache;
          _clientName = _clientName ?? cache.clientName;
          _clientAddress = _clientAddress ?? cache.clientAddress;
          if (_clientLocation == null && cache.clientLat != null && cache.clientLng != null) {
            _clientLocation = LatLng(cache.clientLat!, cache.clientLng!);
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await NotificacionesServicio.instance.showTripNotification(
            title: 'Solicitud activa',
            body: 'Continúa el servicio',
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _initFromSolicitud() async {
    // Si ya viene todo desde el caller, usarlo directamente
 if (widget.clientLocation != null) {

  _clientLocation = widget.clientLocation;
  _driverLocation = widget.driverLocation;
  _clientName = widget.clientName;
  _clientAddress = widget.clientAddress;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(widget.solicitudId)
        .get();

    final data = doc.data();
    final rawCliente = data?['cliente'];

    if (rawCliente is Map) {
      final foto = rawCliente['foto'] ??
          rawCliente['photo'] ??
          rawCliente['photoUrl'] ??
          rawCliente['imagen'];

      if (foto is String && foto.isNotEmpty) {
        _clientPhotoUrl = foto.trim();
      } else if (foto is Map) {
        final url = foto['url'] ?? foto['link'];
        if (url is String && url.isNotEmpty) {
          _clientPhotoUrl = url.trim();
        }
      }
    }
  } catch (_) {}

  setState(() {});
  // Si ya tenemos ubicación del conductor también, solicitar ruta
  if (_driverLocation != null && _clientLocation != null) {
    try {
      await _fetchRouteOSRM(_driverLocation!, _clientLocation!);
    } catch (_) {}
  }
  return;
}


    setState(() {
      _loadingSolicitud = true;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .get();
      if (!doc.exists) {
        setState(() {
          _loadingSolicitud = false;
        });
        return;
      }
      final data = doc.data();
      if (data == null) {
        setState(() {
          _loadingSolicitud = false;
        });
        return;
      }

      LatLng? origen;
      LatLng? conductorPos;

      // origen (cliente): preferir siempre cliente.ubicacion
      final rawCliente = data['cliente'];
      if (rawCliente is Map && rawCliente['ubicacion'] is Map) {
        final cu = Map<String, dynamic>.from(rawCliente['ubicacion']);
        final lat = (cu['lat'] ?? cu['latitude'] ?? cu['latitud']);
        final lng = (cu['lng'] ?? cu['longitude'] ?? cu['longitud']);
        if (lat != null && lng != null) {
          origen = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
        if (rawCliente['nombre'] is String) {
          _clientName = (rawCliente['nombre'] as String).trim();
        }
        // intentar leer foto del cliente desde la solicitud
        if (rawCliente['foto'] is String && (rawCliente['foto'] as String).isNotEmpty) {
          _clientPhotoUrl = (rawCliente['foto'] as String).trim();
          if (kDebugMode) {
            print('RutaConductorView: loaded client photo url: $_clientPhotoUrl');
          }
        }
      }

      // ubicación del conductor desde el objeto 'conductor' en la solicitud
      final rawConductor = data['conductor'];
      if (rawConductor is Map) {
        final lat = (rawConductor['lat'] ?? rawConductor['latitude'] ?? rawConductor['latitud']);
        final lng = (rawConductor['lng'] ?? rawConductor['longitude'] ?? rawConductor['longitud']);
        if (lat != null && lng != null) {
          conductorPos = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }
      }

      setState(() {
        _clientLocation = origen;
        _driverLocation = conductorPos;
        _loadingSolicitud = false;
      });

      if (origen != null && conductorPos != null) {
        await _fetchRouteOSRM(conductorPos, origen);
      }
      // Cache persistence is handled by the ViewModel now.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSolicitud = false;
      });
    }
  }

  

  Future<void> _loadClientMarkerIcon() async {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() {
        _clientMarkerIcon = icon;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    final f1 = _chatSub?.cancel();
    f1?.catchError((e) {
      // ignore platform "No active stream to cancel"
    });
    final f2 = _driverPosSub?.cancel();
    f2?.catchError((e) {
      // ignore platform "No active stream to cancel"
    });
    _viewModel.dispose();
    super.dispose();
  }

  void _handleSolicitudCancelada() {
    if (!mounted) return;
    // Limpia cache de la solicitud cancelada
    RouteCacheService.clearSolicitud(widget.solicitudId);
    // Marcar la solicitud como cancelada en Firestore y mostrar loader antes de volver al inicio
    try {
      FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .update({'status': 'cancelada'});
    } catch (_) {}

    // Mostrar pantalla intermedia de 3 segundos y luego volver al inicio
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoaderSolicitudCanceladaConductorView()),
    );
  }

  void _listenChatMessages() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final f = _chatSub?.cancel();
    f?.catchError((e) {
      // ignore platform "No active stream to cancel"
    });
    _chatSub = _chatService
        .listenMessages(widget.solicitudId)
        .listen((mensajes) {
      if (!mounted) return;
      if (mensajes.isEmpty) return;
      final last = mensajes.last;
      final esDeOtro = last.senderId != uid;
      if (!_isChatOpen && esDeOtro) {
        setState(() {
          _hasNewChat = true;
        });

        final texto = last.texto.trim();
        if (texto.isNotEmpty) {
          _viewModel.notifyNewChatMessage(texto);
        }
      }
    }, onError: (_) {});
  }


  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    // Centrar en el conductor, orientando el mapa hacia el cliente
    try {
      final origin = _driverLocation ?? widget.driverLocation;
      final dest = _clientLocation ?? widget.clientLocation;

      if (origin != null && dest != null) {
        final bearing = _calculateBearing(origin, dest);
        final dist = _haversineDistanceMeters(origin, dest);
        final zoom = _zoomForDistanceMeters(dist);
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: origin,
              zoom: zoom,
              bearing: bearing,
              tilt: 45, // Inclinación para mejor visualización 3D de la ruta
            ),
          ),
        );
      } else if (dest != null) {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(dest, 16),
        );
      }
    } catch (_) {}
  }

  void _maybeFetchRouteIfNeeded() {
    try {
      if ((_routePoints.isEmpty || _polylines.every((p) => p.polylineId.value != 'route')) &&
          _driverLocation != null &&
          (_clientLocation ?? widget.clientLocation) != null) {
        final client = _clientLocation ?? widget.clientLocation!;
        final driver = _driverLocation!;
        // fetch without awaiting to avoid blocking the listener
        _fetchRouteOSRM(driver, client);
      }
    } catch (_) {}
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

  double _zoomForDistanceMeters(double meters) {
    if (meters < 200) return 18;
    if (meters < 500) return 17;
    if (meters < 1000) return 16;
    if (meters < 2000) return 15;
    if (meters < 5000) return 14;
    if (meters < 10000) return 13;
    return 12;
  }

  Future<void> _sendChatMessage() async {
    final texto = _chatController.text.trim();
    if (texto.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _chatService.sendMessage(
        solicitudId: widget.solicitudId,
        senderId: uid ?? '',
        texto: texto,
      );
      _chatController.clear();
      await Future.delayed(const Duration(milliseconds: 60));
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent + 24,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {}
  }

  Future<void> _openChatSheet() async {
    setState(() {
      _isChatOpen = true;
      _hasNewChat = false;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets;
        final keyboardOpen = viewInsets.bottom > 0;
        final initialSize = keyboardOpen ? 0.9 : 0.55;
        final minSize = keyboardOpen ? 0.6 : 0.35;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _chatFocusNode.canRequestFocus) {
            FocusScope.of(ctx).requestFocus(_chatFocusNode);
          }
        });
        return Padding(
          padding: EdgeInsets.only(
            bottom: viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: initialSize,
            minChildSize: minSize,
            maxChildSize: 0.95,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(blurRadius: 16, color: Colors.black26),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.wp(ctx, 3),
                  ResponsiveHelper.hp(ctx, 1.2),
                  ResponsiveHelper.wp(ctx, 3),
                  ResponsiveHelper.hp(ctx, 1.2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chat con tu cliente',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: ResponsiveHelper.sp(ctx, 16),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: ResponsiveHelper.sp(ctx, 18)),
                          onPressed: () {
                            FocusScope.of(ctx).unfocus();
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.hp(ctx, 1.2)),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: StreamBuilder<List<ChatMessage>>(
                          stream: _chatService.listenMessages(widget.solicitudId),
                          initialData: const [],
                          builder: (context, snapshot) {
                            final mensajes = snapshot.data ?? const <ChatMessage>[];
                            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_chatScrollController.hasClients) {
                                _chatScrollController.jumpTo(
                                  _chatScrollController.position.maxScrollExtent,
                                );
                              }
                            });
                            if (mensajes.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Aún no hay mensajes.\nEscribe el primero.',
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            return ListView.builder(
                              controller: _chatScrollController,
                              padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                              itemCount: mensajes.length,
                              itemBuilder: (_, i) {
                                final m = mensajes[i];
                                final esMio = m.senderId == uid;
                                final ts = m.timestamp;
                                final hhmm = ts != null
                                    ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                                    : '';
                                return Align(
                                  alignment: esMio
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: EdgeInsets.symmetric(
                                      vertical: ResponsiveHelper.hp(context, 0.4),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ResponsiveHelper.wp(context, 3),
                                      vertical: ResponsiveHelper.hp(context, 0.8),
                                    ),
                                    constraints: BoxConstraints(
                                      maxWidth: ResponsiveHelper.wp(context, 65),
                                    ),
                                    decoration: BoxDecoration(
                                      color: esMio
                                          ? AppColores.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.black12,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          m.texto,
                                          style: TextStyle(
                                            fontSize: ResponsiveHelper.sp(context, 14),
                                            color: AppColores.textPrimary,
                                          ),
                                        ),
                                        if (hhmm.isNotEmpty) ...[
                                          SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              hhmm,
                                              style: TextStyle(
                                                fontSize: ResponsiveHelper.sp(context, 11),
                                                color: AppColores.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            focusNode: _chatFocusNode,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Escribe un mensaje...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(20)),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.wp(ctx, 3),
                                vertical: ResponsiveHelper.hp(ctx, 0.8),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.wp(ctx, 2)),
                        IconButton(
                          icon: Icon(Icons.send, color: AppColores.primary, size: ResponsiveHelper.sp(ctx, 18)),
                          onPressed: _sendChatMessage,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (mounted) {
      setState(() {
        _isChatOpen = false;
      });
      FocusScope.of(context).unfocus();
    }
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
      });

      // Ajustar cámara centrada en el conductor mirando hacia el cliente con bearing y zoom dinámico
      if (_mapController != null && points.isNotEmpty && points.length >= 2) {
        try {
          final conductorPos = origin;
          final clientePos = dest;
          
          if (conductorPos != null && clientePos != null) {
            final bearing = _calculateBearing(conductorPos, clientePos);
            final dist = _haversineDistanceMeters(conductorPos, clientePos);
            final zoom = _zoomForDistanceMeters(dist);
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: conductorPos,
                  zoom: zoom,
                  bearing: bearing,
                  tilt: 45,
                ),
              ),
            );
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // Posición del conductor ahora llega desde el ViewModel vía stream

  double _haversineDistanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // Radio de la Tierra en metros
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  void _shortenRouteToDriver() {
    try {
      if (_routePoints.isEmpty || _driverLocation == null) return;

      // Si muy cerca del destino, limpiar la polilínea
      final dest = _clientLocation ?? widget.clientLocation;
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

      // Buscar el punto más cercano en la ruta
      int closestIdx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < _routePoints.length; i++) {
        final d = _haversineDistanceMeters(_driverLocation!, _routePoints[i]);
        if (d < minDist) {
          minDist = d;
          closestIdx = i;
        }
      }

      if (closestIdx <= _lastRouteCutIndex) return; // no avanzar corte
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

      // Reorientar cámara hacia el siguiente punto con zoom dinámico
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

  Future<void> _recenterOnRoute() async {
    try {
      if (_mapController == null) return;

      final origin = _driverLocation ?? widget.driverLocation;
      final dest = _clientLocation ?? widget.clientLocation;

      // Si tenemos tanto la ubicación del conductor como del cliente, centramos con bearing y zoom dinámico
      if (origin != null && dest != null) {
        final bearing = _calculateBearing(origin, dest);
        final dist = _haversineDistanceMeters(origin, dest);
        final zoom = _zoomForDistanceMeters(dist);
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: origin,
              zoom: zoom,
              bearing: bearing,
              tilt: 45, // Ligera inclinación para mejor visualización de la ruta
            ),
          ),
        );
        return;
      }

      // Si hay polilíneas, usar sus puntos para ajustar la cámara con bearing
      final allPoints = <LatLng>[];
      for (final poly in _polylines) {
        allPoints.addAll(poly.points);
      }

      if (allPoints.isNotEmpty && allPoints.length >= 2) {
        // Calcular bearing desde el primer punto (conductor) al último (cliente)
        final bearing = _calculateBearing(allPoints.first, allPoints.last);
        final dist = _haversineDistanceMeters(allPoints.first, allPoints.last);
        final zoom = _zoomForDistanceMeters(dist);
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: allPoints.first,
              zoom: zoom,
              bearing: bearing,
              tilt: 45,
            ),
          ),
        );
        return;
      }

      // Fallback: centrar en la ubicación disponible sin bearing
      final target = origin ?? dest;
      if (target != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(target, origin != null ? 15.5 : 16.0),
        );
      }
    } catch (_) {}
  }

  Future<void> _abrirGoogleMapsExternamente() async {
    try {
      final destino = _clientLocation ?? widget.clientLocation;
      if (destino == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encuentra la ubicación del cliente')), 
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

  @override
  Widget build(BuildContext context) {
    final clientLocation = _clientLocation ?? widget.clientLocation;

    // Respetar zonas seguras usando SafeArea (se aplica abajo más abajo).

    if (clientLocation == null || _loadingSolicitud) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: MapLoadingWidget(
              message: 'Cargando mapa de la ruta...',
            ),
          ),
        ),
      );
    }

    final markers = <Marker>{
      Marker(
        markerId: MarkerId('client_${widget.solicitudId}'),
        position: clientLocation,
        icon: _clientMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: _clientName ?? widget.clientName ?? 'Cliente',
          snippet: _clientAddress ?? widget.clientAddress,
        ),
      ),
    };

    // No añadimos un marcador personalizado para el conductor aquí.
    // Dejamos que el propio Google Maps muestre el 'my-location' (punto azul)
    // usando `myLocationEnabled: true` en el widget del mapa.

    // Calcular distancia actual del conductor al cliente (en metros)
    final double _distanceToClient = (_driverLocation == null || clientLocation == null)
      ? double.infinity
      : _haversineDistanceMeters(_driverLocation!, clientLocation);
    final bool _canPressArrived = _distanceToClient <= 50.0; // habilitar solo dentro de 50 metros

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            // Mapa ocupa casi todo el alto disponible
            Expanded(
              child: Stack(
                children: [
                  AppGoogleMap(
                    initialTarget: _driverLocation ?? widget.driverLocation ?? clientLocation,
                    initialZoom: (_driverLocation ?? widget.driverLocation) != null ? 15.5 : 16.0,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    compassEnabled: true,
                    markers: markers,
                    polylines: _polylines,
                    onMapCreated: _onMapCreated,
                  ),
                  // Badge flotante con distancia al cliente
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: SafeArea(
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.place, size: ResponsiveHelper.sp(context, 14), color: _canPressArrived ? Colors.green : AppColores.primary),
                              SizedBox(width: ResponsiveHelper.wp(context, 2)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _distanceToClient.isFinite
                                        ? (_distanceToClient <= 0.5 ? 'A <1 m' : '${_distanceToClient.round()} m')
                                        : 'Calculando...',
                                    style: TextStyle(fontSize: ResponsiveHelper.sp(context, 13), fontWeight: FontWeight.w700, color: _canPressArrived ? Colors.green : AppColores.textPrimary),
                                  ),
                                  
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_routeDurationMin != null)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: EdgeInsets.only(top: ResponsiveHelper.hp(context, 2)),
                        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 3), vertical: ResponsiveHelper.hp(context, 1)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(blurRadius: 6, color: Colors.black26),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: ResponsiveHelper.sp(context, 14), color: AppColores.textSecondary),
                            SizedBox(width: ResponsiveHelper.wp(context, 2)),
                            Text(
                              'Tiempo estimado: ${_routeDurationMin} min',
                              style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14), fontWeight: FontWeight.w600, color: AppColores.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Información del cliente + botones (estilo card inferior)
            Container(
              width: double.infinity,
              // Dejar un pequeño margen inferior para que el card no quede
              // pegado al borde. `SafeArea(bottom: true)` ya protege
              // contra la barra de navegación, así evitamos duplicar inset.
              margin: EdgeInsets.only(bottom: ResponsiveHelper.hp(context, 1)),
              constraints: BoxConstraints(minHeight: ResponsiveHelper.hp(context, 18)),
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
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.wp(context, 4),
                ResponsiveHelper.hp(context, 2),
                ResponsiveHelper.wp(context, 4),
                ResponsiveHelper.hp(context, 2) + ResponsiveHelper.hp(context, 0.8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Imagen del cliente (rectangular redondeada) junto al nombre
                      (_clientPhotoUrl != null && _clientPhotoUrl!.isNotEmpty)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _clientPhotoUrl!,
                                width: ResponsiveHelper.sp(context, 60),
                                height: ResponsiveHelper.sp(context, 60),
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, error, stack) => Container(
                                  width: ResponsiveHelper.sp(context, 60),
                                  height: ResponsiveHelper.sp(context, 60),
                                  color: Colors.grey.shade200,
                                  child: Icon(
                                    Icons.person,
                                    size: ResponsiveHelper.sp(context, 18),
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: ResponsiveHelper.sp(context, 60),
                              height: ResponsiveHelper.sp(context, 60),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.person,
                                size: ResponsiveHelper.sp(context, 18),
                                color: Colors.black87,
                              ),
                            ),
                      SizedBox(width: ResponsiveHelper.wp(context, 3)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _clientName ?? widget.clientName ?? 'Cliente',
                                    style: TextStyle(
                                      fontSize: ResponsiveHelper.sp(context, 18),
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.chat_bubble_outline),
                                      if (_hasNewChat)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  onPressed: _openChatSheet,
                                ),
                              ],
                            ),
                            if (((_clientAddress ?? widget.clientAddress) ?? '').isNotEmpty) ...[
                              SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                              Text(
                                (_clientAddress ?? widget.clientAddress)!,
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 13),
                                  color: Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.hp(context, 2)),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _abrirGoogleMapsExternamente,
                          icon: Icon(Icons.navigation_outlined, size: ResponsiveHelper.sp(context, 16)),
                          label: Text('Mapa', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColores.primary,
                            side: BorderSide(color: AppColores.primary),
                            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.wp(context, 3)),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _canPressArrived ? () async {
                            try {
                              await FirebaseFirestore.instance
                                  .collection('solicitudes')
                                  .doc(widget.solicitudId)
                                  .update({'status': 'en camino'});
                            } catch (_) {}

                            if (widget.onArrived != null) {
                              widget.onArrived!();
                              return;
                            }
                            if (!mounted) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RutaDestinoConductorView(
                                  solicitudId: widget.solicitudId,
                                ),
                              ),
                            );
                          } : null,
                          icon: Icon(Icons.check_circle_outline, size: ResponsiveHelper.sp(context, 16)),
                          label: Text('Ya llegué', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _canPressArrived ? AppColores.primary : Colors.grey.shade400,
                            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
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
}

/// Pantalla intermedia que muestra un loader mientras
/// se prepara la ruta del conductor hacia el cliente.
class RutaConductorLoadingView extends StatefulWidget {
  final String solicitudId;
  final LatLng clientLocation;
  final String? clientName;
  final String? clientAddress;
  final LatLng? driverLocation;

  const RutaConductorLoadingView({
    Key? key,
    required this.solicitudId,
    required this.clientLocation,
    this.clientName,
    this.clientAddress,
    this.driverLocation,
  }) : super(key: key);

  @override
  State<RutaConductorLoadingView> createState() => _RutaConductorLoadingViewState();
}

class _RutaConductorLoadingViewState extends State<RutaConductorLoadingView> {
  @override
  void initState() {
    super.initState();
    _goToRouteAfterDelay();
  }

  void _goToRouteAfterDelay() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RutaConductorView(
            solicitudId: widget.solicitudId,
            clientLocation: widget.clientLocation,
            clientName: widget.clientName,
            clientAddress: widget.clientAddress,
            driverLocation: widget.driverLocation,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: MapLoadingWidget(
            message: 'Cargando mapa de la ruta...',
          ),
        ),
      ),
    );
  }
}

/// Pantalla intermedia para el conductor que muestra un loader
/// de "Volviendo atrás..." y luego regresa a la pantalla anterior.
class LoaderVolviendoAtrasConductorView extends StatefulWidget {
  const LoaderVolviendoAtrasConductorView({Key? key}) : super(key: key);

  @override
  State<LoaderVolviendoAtrasConductorView> createState() => _LoaderVolviendoAtrasConductorViewState();
}

class LoaderSolicitudCanceladaConductorView extends StatefulWidget {
  const LoaderSolicitudCanceladaConductorView({Key? key}) : super(key: key);

  @override
  State<LoaderSolicitudCanceladaConductorView> createState() => _LoaderSolicitudCanceladaConductorViewState();
}

class _LoaderSolicitudCanceladaConductorViewState extends State<LoaderSolicitudCanceladaConductorView> {
  @override
  void initState() {
    super.initState();
    _goBackAfterDelay();
  }

  void _goBackAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeConductorMapView()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: MapLoadingWidget(
            message: 'Solicitud cancelada',
          ),
        ),
      ),
    );
  }
}

class _LoaderVolviendoAtrasConductorViewState extends State<LoaderVolviendoAtrasConductorView> {
  @override
  void initState() {
    super.initState();
    _goBackAfterDelay();
  }

  void _goBackAfterDelay() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      try {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeConductorMapView()),
          (route) => false,
        );
      } catch (_) {
        // En caso de error con el Navigator, intentar un pop seguro como fallback
        try {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: MapLoadingWidget(
            message: 'Volviendo atrás... Solicitud a sido cancelada'
          ),
        ),
      ),
    );
  }
}
