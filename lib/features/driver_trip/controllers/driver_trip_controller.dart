import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_route_math_service.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/driver_chat_message.dart';
import '../models/driver_trip_model.dart';
import '../services/driver_location_service.dart';
import '../services/driver_route_service.dart';
import '../services/driver_trip_firestore_service.dart';

enum DriverMapFocusMode { clientOnly, both }

enum DriverPendingNavigation { none, inicioConductor, rutaDestino }

class DriverTripController extends ChangeNotifier {
  DriverTripController({
    required this.tripId,
    DriverTripFirestoreService? firestoreService,
    DriverRouteService? routeService,
    DriverLocationService? locationService,
  }) : _firestoreService = firestoreService ?? DriverTripFirestoreService(),
       _routeService = routeService ?? DriverRouteService(),
       _locationService = locationService ?? DriverLocationService();

  final String tripId;
  final DriverTripFirestoreService _firestoreService;
  final DriverRouteService _routeService;
  final DriverLocationService _locationService;
  final TripRouteMathService _mathService = const TripRouteMathService();

  DriverTripModel? trip;
  List<DriverChatMessage> messages = const [];
  List<LatLng> routePoints = const [];
  double? distanceMeters;
  Duration? eta;
  double driverHeading = 0.0;

  bool isLoading = true;
  bool isRouteLoading = false;
  bool isSendingArrival = false;
  bool isWaitingActionLoading = false;
  bool _hasReportedArrival = false;

  /// Indica si la app está actualmente en segundo plano.
  /// Se actualiza desde la pantalla via [setAppBackground].
  bool isAppInBackground = false;

  int unreadCount = 0;
  DriverMapFocusMode focusMode = DriverMapFocusMode.clientOnly;

  bool waitingModalVisible = false;
  bool waitingCanStartTrip = false;
  int waitingRemainingSeconds = 180;

  DriverPendingNavigation _pendingNavigation = DriverPendingNavigation.none;
  DriverPendingNavigation get pendingNavigation => _pendingNavigation;

  String? errorText;

  StreamSubscription<DriverTripModel>? _tripSub;
  StreamSubscription<List<DriverChatMessage>>? _messagesSub;
  Timer? _waitingTimer;

  String? _lastStatus;
  LatLng? _lastFrom;
  LatLng? _lastTo;
  bool _disposed = false;
  bool _messageBootstrapComplete = false;
  bool _notificationsReady = false;
  bool _loadNotificationShown = false;
  bool _timeoutStatusUpdating = false;
  String? _pendingInfoMessage;

  String? consumePendingInfoMessage() {
    final message = _pendingInfoMessage;
    _pendingInfoMessage = null;
    return message;
  }

  String get currentDriverId => _locationService.currentDriverUid ?? '';

  String get distanceText {
    final d = distanceMeters;
    if (d == null) return '--';
    return _routeService.formatDistance(d);
  }

  String get etaText {
    final e = eta;
    if (e == null) return '--';
    return _routeService.formatEta(e);
  }

  LatLng? get clientLatLng {
    final c = trip?.client;
    if (c == null || !c.hasLocation) return null;
    return LatLng(c.lat!, c.lng!);
  }

  LatLng? get driverLatLng {
    final d = trip?.driver;
    if (d == null || !d.hasLocation) return null;
    return LatLng(d.lat!, d.lng!);
  }

  String get clientName {
    final name = trip?.client.name ?? '';
    return name.isNotEmpty ? name : 'Cliente';
  }

  String get clientAddress {
    return trip?.client.address ?? '';
  }

  String get clientPhotoUrl {
    return trip?.client.photoUrl ?? '';
  }

  bool get hasBothLocations => clientLatLng != null && driverLatLng != null;

  Future<void> init() async {
    await _ensureNotifications();
    await _notifyLoadIfNeeded();

    _bindTrip();
    _bindMessages();

    try {
      await _locationService.startRealtimeSync(tripId: tripId);
    } catch (e) {
      errorText = 'No se pudo iniciar tracking GPS: $e';
      _safeNotify();
    }
  }

  Future<void> toggleMapFocusMode() async {
    focusMode = focusMode == DriverMapFocusMode.clientOnly
        ? DriverMapFocusMode.both
        : DriverMapFocusMode.clientOnly;
    _safeNotify();
  }

  CameraPosition? getCameraPerspective() {
    final driver = driverLatLng;
    final client = clientLatLng;
    if (driver == null || client == null) return null;

    final bearing = _mathService.bearingBetween(driver, client);
    return CameraPosition(
      target: driver,
      bearing: bearing,
      tilt: 0.0,
      zoom: 16.5,
    );
  }

  /// Llamar desde [DriverTripScreen.didChangeAppLifecycleState] para
  /// mantener sincronizado el flag de segundo plano.
  void setAppBackground(bool inBackground) {
    isAppInBackground = inBackground;
  }

  Future<void> sendMessage(String text) {
    return _firestoreService.sendMessage(
      tripId: tripId,
      senderId: currentDriverId,
      text: text,
    );
  }

  Future<void> markChatAsRead() async {
    await _firestoreService.markAllMessagesAsRead(
      tripId: tripId,
      userId: currentDriverId,
      messages: messages,
    );

    messages = messages
        .map(
          (m) => m.senderId == currentDriverId
              ? m
              : DriverChatMessage(
                  id: m.id,
                  senderId: m.senderId,
                  text: m.text,
                  timestamp: m.timestamp,
                  readBy: {...m.readBy, currentDriverId: true},
                ),
        )
        .toList(growable: false);

    _computeUnreadCount();
    _safeNotify();
  }

  Future<void> reportArrival() async {
    if (isSendingArrival || _hasReportedArrival) return;

    isSendingArrival = true;
    _safeNotify();

    try {
      await _firestoreService.updateTripStatus(
        tripId: tripId,
        status: 'en espera',
      );
      _hasReportedArrival = true;
      _openWaitingModal();
    } finally {
      isSendingArrival = false;
      _safeNotify();
    }
  }

  bool get hasReportedArrival => _hasReportedArrival;

  Future<bool> beginTripAfterClientConfirm() async {
    final statusActual = normalizeStatus(trip?.status ?? '');
    final puedeIniciar = waitingCanStartTrip || statusActual == 'en_camino';
    if (!puedeIniciar || isWaitingActionLoading) return false;

    isWaitingActionLoading = true;
    _safeNotify();

    try {
      await _firestoreService.updateTripStatus(
        tripId: tripId,
        status: 'en ruta',
      );
      _closeWaitingModal();
      _setPendingNavigation(DriverPendingNavigation.rutaDestino);
      return true;
    } catch (e) {
      errorText = 'No se pudo iniciar ruta: $e';
      return false;
    } finally {
      isWaitingActionLoading = false;
      _safeNotify();
    }
  }

  void consumePendingNavigation() {
    _pendingNavigation = DriverPendingNavigation.none;
  }

  Future<void> onAppResumed() async {
    try {
      await _locationService.syncOneShotToTrip(tripId: tripId);
    } catch (_) {}
  }

  Future<void> _bindTrip() async {
    _tripSub?.cancel();
    _tripSub = _firestoreService
        .watchTrip(tripId)
        .listen(
          (incoming) async {
            trip = incoming;
            isLoading = false;
            errorText = null;
            _safeNotify();

            _handleStatusTransition(incoming.status);
            await _refreshRouteIfNeeded();
          },
          onError: (error) {
            isLoading = false;
            errorText = 'No se pudo cargar solicitud: $error';
            _safeNotify();
          },
        );
  }

  void _bindMessages() {
    _messagesSub?.cancel();
    _messagesSub = _firestoreService.watchMessages(tripId).listen((
      incoming,
    ) async {
      if (_messageBootstrapComplete) {
        final previousIds = messages.map((m) => m.id).toSet();
        final newExternalMessages = incoming.where(
          (m) => !previousIds.contains(m.id) && m.senderId != currentDriverId,
        );

        for (final msg in newExternalMessages) {
          try {
            await NotificacionesServicio.instance.showChatNotification(
              senderName: '💬 Nuevo mensaje del cliente',
              message: msg.text,
            );
          } catch (_) {}
        }
      } else {
        _messageBootstrapComplete = true;
      }

      messages = incoming;
      _computeUnreadCount();
      _safeNotify();
    });
  }

  void _computeUnreadCount() {
    unreadCount = messages
        .where(
          (m) => m.senderId != currentDriverId && !m.isReadBy(currentDriverId),
        )
        .length;
  }

  void _handleStatusTransition(String rawStatus) {
    final status = normalizeStatus(rawStatus);
    if (_lastStatus == status) return;
    _lastStatus = status;

    if (status == 'cancelado') {
      _closeWaitingModal();
      unawaited(_notify('Viaje cancelado', 'Viaje cancelado.'));
      _setPendingNavigation(DriverPendingNavigation.inicioConductor);
      return;
    }

    if (status == 'sin_respuesta') {
      _closeWaitingModal();
      _pendingInfoMessage =
          'El cliente no respondio a tiempo. La solicitud fue cancelada por sin respuesta.';
      // Solo notificar si la app está en segundo plano
      if (isAppInBackground) {
        unawaited(
          NotificacionesServicio.instance.showTripNotification(
            title: '⚠️ Sin respuesta del cliente',
            body:
                'El cliente no contestó la validación, se cancelará el servicio.',
          ),
        );
      }
      _setPendingNavigation(DriverPendingNavigation.inicioConductor);
      return;
    }

    if (status == 'en_ruta') {
      _closeWaitingModal();
      _setPendingNavigation(DriverPendingNavigation.rutaDestino);
      return;
    }

    if (status == 'en_espera') {
      _openWaitingModal();
      waitingCanStartTrip = false;
      _safeNotify();
      return;
    }

    if (status == 'en_camino') {
      if (!waitingModalVisible) {
        _openWaitingModal();
      }
      waitingCanStartTrip = true;
      _stopWaitingTimer();
      // Solo notificar si la app está en segundo plano
      if (isAppInBackground) {
        unawaited(
          NotificacionesServicio.instance.showTripNotification(
            title: '✅ Cliente ha confirmado',
            body: 'El cliente ha confirmado su asistencia, ya viene en camino.',
          ),
        );
      }
      _safeNotify();
      return;
    }

    _closeWaitingModal();
  }

  Future<void> _refreshRouteIfNeeded() async {
    if (!hasBothLocations || isRouteLoading) return;

    final from = driverLatLng!;
    final to = clientLatLng!;

    final shouldRefresh =
        _lastFrom == null ||
        _lastTo == null ||
        _routeService.distanceMeters(_lastFrom!, from) > 20 ||
        _routeService.distanceMeters(_lastTo!, to) > 20;

    if (!shouldRefresh) return;

    isRouteLoading = true;
    _safeNotify();

    try {
      final polyline = await _routeService.fetchRoutePolyline(
        from: from,
        to: to,
      );
      final dist = _routeService.polylineDistanceMeters(polyline);

      routePoints = polyline;
      distanceMeters = dist;
      eta = _routeService.etaFromDistance(dist);

      // Update heading after route refresh.
      try {
        final current = driverLatLng;
        if (current != null && routePoints.length >= 2) {
          final nearest = _mathService.nearestPointIndex(current, routePoints);
          LatLng? target;
          if (nearest < routePoints.length - 1) {
            target = routePoints[nearest + 1];
          } else if (nearest > 0) {
            target = routePoints[nearest];
          }
          if (target != null) {
            driverHeading = _mathService.bearingBetween(current, target);
          }
        }
      } catch (_) {
        driverHeading = 0.0;
      }

      _lastFrom = from;
      _lastTo = to;
    } finally {
      isRouteLoading = false;
      _safeNotify();
    }
  }

  void _openWaitingModal() {
    if (waitingModalVisible) return;

    waitingModalVisible = true;
    waitingCanStartTrip = false;
    waitingRemainingSeconds = 180;

    _stopWaitingTimer();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (waitingCanStartTrip) {
        _stopWaitingTimer();
        return;
      }

      if (waitingRemainingSeconds <= 0) {
        waitingRemainingSeconds = 0;
        _stopWaitingTimer();
        unawaited(_handleWaitingTimeoutNoResponse());
        _safeNotify();
        return;
      }
      waitingRemainingSeconds -= 1;
      _safeNotify();
    });

    _safeNotify();
  }

  void _closeWaitingModal() {
    if (!waitingModalVisible && _waitingTimer == null) return;

    waitingModalVisible = false;
    waitingCanStartTrip = false;
    isWaitingActionLoading = false;
    _stopWaitingTimer();
    _safeNotify();
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    await NotificacionesServicio.instance.init();
    _notificationsReady = true;
  }

  Future<void> _notifyLoadIfNeeded() async {
    if (_loadNotificationShown) return;
    _loadNotificationShown = true;
    await _notify('Cliente asignado', 'Viaja a recoger al cliente.');
  }

  Future<void> _notify(String title, String body) async {
    try {
      await _ensureNotifications();
      await NotificacionesServicio.instance.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
      );
    } catch (_) {}
  }

  void _setPendingNavigation(DriverPendingNavigation target) {
    if (_pendingNavigation == target) return;
    _pendingNavigation = target;
    _safeNotify();
  }

  Future<void> _handleWaitingTimeoutNoResponse() async {
    if (_timeoutStatusUpdating) return;
    final statusActual = normalizeStatus(trip?.status ?? '');
    if (statusActual == 'en_camino' ||
        statusActual == 'en_ruta' ||
        statusActual == 'cancelado' ||
        statusActual == 'sin_respuesta') {
      return;
    }

    _timeoutStatusUpdating = true;
    try {
      await _firestoreService.updateTripStatus(
        tripId: tripId,
        status: SolicitudEstado.sinRespuesta,
      );
    } catch (e) {
      errorText = 'No se pudo marcar sin respuesta: $e';
      _safeNotify();
    } finally {
      _timeoutStatusUpdating = false;
    }
  }

  static String normalizeStatus(String raw) {
    final value = raw
        .toLowerCase()
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    if (value.contains('cancel')) return 'cancelado';
    if (value.contains('sin respuesta') || value.contains('sinrespuesta')) {
      return 'sin_respuesta';
    }
    if (value.contains('en ruta') || value.contains('enruta')) return 'en_ruta';
    if (value.contains('en camino') || value.contains('encam'))
      return 'en_camino';
    if (value.contains('en espera') || value.contains('enespera'))
      return 'en_espera';
    return value;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tripSub?.cancel();
    _messagesSub?.cancel();
    _stopWaitingTimer();
    _locationService.stopRealtimeSync();
    super.dispose();
  }
}
