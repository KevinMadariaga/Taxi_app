import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/mensaje_model.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/solicitud_model.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/chat_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/map_service.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';

/// Reemplaza el plugin real de connectivity_plus (MethodChannel) para que
/// `_bindConnectivity()` no lance MissingPluginException en tests puros.
/// Siempre reporta "online" — la lógica de offline/reconexión no se
/// caracteriza en esta primera tanda de tests.
class FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
}

/// Sustituye únicamente `fetchRoadPolyline` (la única llamada de red/Cloud
/// Function de MapService). El resto de los métodos (distanceMeters,
/// routeDistanceMeters, etaFromDistance, formatDistance, formatEta) son
/// puros y se reusan de la implementación real sin riesgo.
class FakeMapService extends MapService {
  int fetchCount = 0;

  @override
  Future<List<LatLng>> fetchRoadPolyline({
    required LatLng from,
    required LatLng to,
  }) async {
    fetchCount++;
    return [from, to];
  }
}

/// Sustituye las dos únicas llamadas que `TripTrackingViewModel` hace sobre
/// `TripTrackingFirebaseService`: el stream de la solicitud y cancelar.
class FakeTripTrackingFirebaseService extends TripTrackingFirebaseService {
  FakeTripTrackingFirebaseService(this._stream);

  final Stream<SolicitudModel> _stream;
  int cancelCount = 0;
  String? lastCancelledBy;

  @override
  Stream<SolicitudModel> watchSolicitud(String solicitudId) => _stream;

  @override
  Future<void> cancelarSolicitud({
    required String solicitudId,
    required String cancelledBy,
  }) async {
    cancelCount++;
    lastCancelledBy = cancelledBy;
  }
}

/// Fake de ChatService. Por defecto expone un stream vacío (suficiente para
/// los tests de `TripTrackingViewModel`, donde el chat está fuera de
/// alcance); pasar [messagesStream] para caracterizar `TripChatController`
/// directamente, controlando qué llega y cuándo.
class FakeChatService extends ChatService {
  FakeChatService({Stream<List<MensajeModel>>? messagesStream})
    : _messagesStream = messagesStream ?? const Stream<List<MensajeModel>>.empty();

  final Stream<List<MensajeModel>> _messagesStream;

  int sendCount = 0;
  String? lastSendTexto;
  String? lastSendSenderId;

  int markAllAsReadCount = 0;
  List<MensajeModel>? lastMarkAllAsReadMessages;

  @override
  Stream<List<MensajeModel>> watchMessages(String solicitudId) =>
      _messagesStream;

  @override
  Future<void> sendMessage({
    required String solicitudId,
    required String senderId,
    required String texto,
  }) async {
    sendCount++;
    lastSendSenderId = senderId;
    lastSendTexto = texto;
  }

  @override
  Future<void> markAllAsRead({
    required String solicitudId,
    required String userId,
    required List<MensajeModel> messages,
  }) async {
    markAllAsReadCount++;
    lastMarkAllAsReadMessages = messages;
  }
}
