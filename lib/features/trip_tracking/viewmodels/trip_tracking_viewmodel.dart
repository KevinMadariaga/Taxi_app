import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/services/notification_service.dart';

import '../models/mensaje_model.dart';
import '../models/solicitud_model.dart';
import '../services/chat_service.dart';
import '../services/firebase_service.dart';
import '../services/local_cache_service.dart';
import '../services/map_service.dart';

enum MapFocusMode { clientOnly, both }

class TripTrackingViewModel extends ChangeNotifier {
  // Notificaciones:
  // - Local notifications (gratis) para avisos en app activa.
  // - Para escenarios mas robustos en segundo plano/cross-device, se recomienda FCM
  //   (tambien con capa gratuita) o proveedores enterprise si se requiere SLA avanzado.
  TripTrackingViewModel({
    required this.solicitudId,
    required this.currentUserId,
    required this.cancelledBy,
    FirebaseService? firebaseService,
    MapService? mapService,
    ChatService? chatService,
    LocalCacheService? localCacheService,
  }) : _firebaseService = firebaseService ?? FirebaseService(),
       _mapService = mapService ?? MapService(),
       _chatService = chatService ?? ChatService(),
       _localCacheService = localCacheService ?? LocalCacheService();

  final String solicitudId;
  final String currentUserId;
  final String cancelledBy;

  final FirebaseService _firebaseService;
  final MapService _mapService;
  final ChatService _chatService;
  final LocalCacheService _localCacheService;

  SolicitudModel? solicitud;
  List<LatLng> routePoints = const [];
  double? distanceMeters;
  Duration? eta;

  List<MensajeModel> messages = const [];
  int unreadCount = 0;

  bool isLoading = true;
  bool isUpdatingRoute = false;
  bool isCancelling = false;
  bool isOffline = false;

  MapFocusMode focusMode = MapFocusMode.clientOnly;

  String? errorText;

  StreamSubscription<SolicitudModel>? _solicitudSub;
  StreamSubscription<List<MensajeModel>>? _messagesSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _disposed = false;
  bool _chatBootstrapped = false;
  bool _notificationInitialized = false;

  LatLng? _lastFrom;
  LatLng? _lastTo;

  Future<void> init() async {
    await _restoreFromCache();
    await _bindConnectivity();
    _bindSolicitud();
    _bindMessages();
  }

  LatLng? get clienteLatLng {
    final c = solicitud?.cliente;
    if (c == null || !c.hasLocation) return null;
    return LatLng(c.lat!, c.lng!);
  }

  LatLng? get conductorLatLng {
    final d = solicitud?.conductor;
    if (d == null || !d.hasLocation) return null;
    return LatLng(d.lat!, d.lng!);
  }

  bool get hasBothLocations => clienteLatLng != null && conductorLatLng != null;

  String get distanciaTexto {
    final d = distanceMeters;
    if (d == null) return '--';
    return _mapService.formatDistance(d);
  }

  String get etaTexto {
    final e = eta;
    if (e == null) return '--';
    return _mapService.formatEta(e);
  }

  String get nombreCliente => solicitud?.cliente.nombre.isNotEmpty == true
      ? solicitud!.cliente.nombre
      : 'Cliente';

  String get nombreConductor => solicitud?.conductor.nombre.isNotEmpty == true
      ? solicitud!.conductor.nombre
      : 'Conductor';

  String get fotoUsuario {
    if (_isCurrentUserCliente) {
      return solicitud?.conductor.fotoUrl ?? '';
    }
    return solicitud?.cliente.fotoUrl ?? '';
  }

  String get nombreUsuarioCard {
    return _isCurrentUserCliente ? nombreConductor : nombreCliente;
  }

  String get fotoVehiculo {
    if (_isCurrentUserCliente) {
      return solicitud?.conductor.fotoVehiculoUrl ?? '';
    }
    return '';
  }

  bool get _isCurrentUserCliente => solicitud?.cliente.id == currentUserId;

  Future<void> toggleMapFocusMode() async {
    focusMode = focusMode == MapFocusMode.clientOnly
        ? MapFocusMode.both
        : MapFocusMode.clientOnly;
    _safeNotify();
  }

  Future<void> sendMessage(String text) {
    return _chatService.sendMessage(
      solicitudId: solicitudId,
      senderId: currentUserId,
      texto: text,
    );
  }

  Future<void> markChatAsRead() async {
    if (messages.isEmpty) return;
    await _chatService.markAllAsRead(
      solicitudId: solicitudId,
      userId: currentUserId,
      messages: messages,
    );

    messages = messages
        .map(
          (m) => m.senderId == currentUserId
              ? m
              : MensajeModel(
                  id: m.id,
                  senderId: m.senderId,
                  texto: m.texto,
                  timestamp: m.timestamp,
                  readBy: {...m.readBy, currentUserId: true},
                ),
        )
        .toList(growable: false);
    _computeUnreadCount();
    _safeNotify();
  }

  Future<void> cancelSolicitud() async {
    if (isCancelling) return;

    isCancelling = true;
    _safeNotify();

    try {
      await _firebaseService.cancelarSolicitud(
        solicitudId: solicitudId,
        cancelledBy: cancelledBy,
      );
      await _localCacheService.clearSolicitudData(solicitudId);
    } finally {
      isCancelling = false;
      _safeNotify();
    }
  }

  void _bindSolicitud() {
    _solicitudSub?.cancel();
    _solicitudSub = _firebaseService
        .watchSolicitud(solicitudId)
        .listen(
          (item) async {
            solicitud = item;
            isLoading = false;
            errorText = null;
            _safeNotify();

            await _localCacheService.saveSolicitud(item);

            await _updateRouteIfNeeded();
          },
          onError: (error) async {
            isLoading = false;

            final cached = await _localCacheService.readSolicitud(solicitudId);
            if (cached != null) {
              solicitud = cached;
              errorText = 'Sin conexion: mostrando datos en cache';
            } else {
              errorText = 'No se pudo cargar la solicitud: $error';
            }

            _safeNotify();
          },
        );
  }

  void _bindMessages() {
    _messagesSub?.cancel();
    _messagesSub = _chatService
        .watchMessages(solicitudId)
        .listen(
          (incoming) async {
            if (_chatBootstrapped) {
              final previousIds = messages.map((m) => m.id).toSet();
              final newIncoming = incoming.where(
                (m) =>
                    !previousIds.contains(m.id) && m.senderId != currentUserId,
              );

              for (final item in newIncoming) {
                await _showMessageNotification(item.texto);
              }
            } else {
              _chatBootstrapped = true;
            }

            messages = incoming;
            _computeUnreadCount();

            await _localCacheService.saveMessages(
              solicitudId: solicitudId,
              messages: incoming,
            );

            _safeNotify();
          },
          onError: (error) async {
            final cachedMessages = await _localCacheService.readMessages(
              solicitudId,
            );
            if (cachedMessages.isNotEmpty) {
              messages = cachedMessages;
              _computeUnreadCount();
              _safeNotify();
            }
          },
        );
  }

  Future<void> _bindConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    isOffline = _isOfflineFromConnectivity(result);

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final nextOffline = _isOfflineFromConnectivity(result);
      if (isOffline == nextOffline) return;
      isOffline = nextOffline;
      _safeNotify();

      if (!isOffline) {
        _updateRouteIfNeeded(forceRefresh: true);
      }
    });
  }

  bool _isOfflineFromConnectivity(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((item) => item == ConnectivityResult.none);
  }

  Future<void> _restoreFromCache() async {
    final cachedSolicitud = await _localCacheService.readSolicitud(solicitudId);
    if (cachedSolicitud != null) {
      solicitud = cachedSolicitud;
      isLoading = false;
    }

    final cachedRoute = await _localCacheService.readRoute(solicitudId);
    if (cachedRoute != null && cachedRoute.points.length >= 2) {
      routePoints = cachedRoute.points;
      distanceMeters = cachedRoute.distanceMeters;
      eta = cachedRoute.etaSeconds != null
          ? Duration(seconds: cachedRoute.etaSeconds!)
          : null;
    }

    final cachedMessages = await _localCacheService.readMessages(solicitudId);
    if (cachedMessages.isNotEmpty) {
      messages = cachedMessages;
      _computeUnreadCount();
    }

    _safeNotify();
  }

  Future<void> _updateRouteIfNeeded({bool forceRefresh = false}) async {
    if (!hasBothLocations || isUpdatingRoute) return;

    final from = conductorLatLng!;
    final to = clienteLatLng!;

    final shouldRefresh =
        _lastFrom == null ||
        _lastTo == null ||
        _mapService.distanceMeters(_lastFrom!, from) > 20 ||
        _mapService.distanceMeters(_lastTo!, to) > 20;

    if (!forceRefresh && !shouldRefresh) return;

    if (isOffline && routePoints.length >= 2 && !forceRefresh) {
      return;
    }

    isUpdatingRoute = true;
    _safeNotify();

    try {
      final points = await _mapService.fetchRoadPolyline(from: from, to: to);
      final distance = _mapService.routeDistanceMeters(points);

      routePoints = points;
      distanceMeters = distance;
      eta = _mapService.etaFromDistance(distance);

      await _localCacheService.saveRoute(
        solicitudId: solicitudId,
        points: points,
        distanceMeters: distance,
        etaSeconds: eta?.inSeconds,
      );

      _lastFrom = from;
      _lastTo = to;
    } catch (_) {
      // No rompe la UI: conserva la ultima ruta valida.
    } finally {
      isUpdatingRoute = false;
      _safeNotify();
    }
  }

  Future<void> _showMessageNotification(String body) async {
    try {
      if (!_notificationInitialized) {
        await NotificationService.instance.init();
        _notificationInitialized = true;
      }

      await NotificationService.instance.showNotification(
        DateTime.now().millisecondsSinceEpoch % 100000,
        'Nuevo mensaje',
        body,
      );
    } catch (_) {
      // Sin bloquear la UX si notificaciones no estan disponibles.
    }
  }

  void _computeUnreadCount() {
    unreadCount = messages
        .where((m) => m.senderId != currentUserId && !m.isReadBy(currentUserId))
        .length;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _solicitudSub?.cancel();
    _messagesSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
