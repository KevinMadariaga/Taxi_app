import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:taxi_app/core/services/chat_firestore_datasource.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/mensaje_model.dart';

/// Chat del viaje, compartido por cliente y conductor — reemplaza
/// `TripChatController` (solo cliente) y la lógica de chat ad-hoc mezclada
/// dentro de `DriverTripController` (solo conductor), que apuntaban a la
/// misma colección `solicitudes/{id}/mensajes` de forma duplicada.
///
/// Sin caché local propia (a diferencia de `TripChatController`, que
/// delegaba en `LocalCacheService`): el chat en vivo no necesita
/// restauración offline para este rebuild — si se requiere más adelante, se
/// agrega igual que las demás piezas, inyectando el servicio.
class ChatController {
  ChatController({
    required this.viajeId,
    required this.currentUserId,
    required this.otherPartyLabel,
    ChatFirestoreDatasource? datasource,
    NotificacionesServicio? notificationService,
  }) : _datasource = datasource ?? ChatFirestoreDatasource(),
       _notificationService =
           notificationService ?? NotificacionesServicio.instance;

  final String viajeId;
  final String currentUserId;

  /// Ej. "conductor" o "cliente" — usado en el texto de la notificación
  /// local de mensaje nuevo.
  final String otherPartyLabel;

  final ChatFirestoreDatasource _datasource;
  final NotificacionesServicio _notificationService;

  List<MensajeModel> messages = const [];
  int unreadCount = 0;

  StreamSubscription<List<MensajeModel>>? _messagesSub;
  bool _bootstrapped = false;

  /// Se dispara con cada cambio de `messages`/`unreadCount`.
  VoidCallback? onChanged;

  void bind() {
    _messagesSub?.cancel();
    _messagesSub = _datasource
        .watchOrderedMessages(viajeId)
        .map(
          (snap) => snap.docs.map(MensajeModel.fromDoc).toList(growable: false),
        )
        .listen((incoming) async {
          if (_bootstrapped) {
            final previousIds = messages.map((m) => m.id).toSet();
            final newIncoming = incoming.where(
              (m) => !previousIds.contains(m.id) && m.senderId != currentUserId,
            );
            for (final item in newIncoming) {
              await _showMessageNotification(item.texto);
            }
          } else {
            _bootstrapped = true;
          }

          messages = incoming;
          _computeUnreadCount();
          onChanged?.call();
        });
  }

  Future<void> sendMessage(String text) {
    return _datasource.sendMessage(
      solicitudId: viajeId,
      senderId: currentUserId,
      texto: text,
    );
  }

  Future<void> markAllAsRead() async {
    final pending = messages.where(
      (m) => m.senderId != currentUserId && !m.isReadBy(currentUserId),
    );
    if (pending.isEmpty) return;

    for (final message in pending) {
      await _datasource.markMessageRead(
        solicitudId: viajeId,
        messageId: message.id,
        userId: currentUserId,
      );
    }

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
    onChanged?.call();
  }

  void _computeUnreadCount() {
    unreadCount = messages
        .where((m) => m.senderId != currentUserId && !m.isReadBy(currentUserId))
        .length;
  }

  Future<void> _showMessageNotification(String body) async {
    try {
      await _notificationService.showChatNotification(
        senderName: '\u{1F4AC} Nuevo mensaje del $otherPartyLabel',
        message: body,
        // Formato consumido por `_manejarTapNotificacion` en main.dart para
        // abrir el chat de este viaje al tocar la notificación.
        payload: 'viaje_chat:$viajeId:$currentUserId:$otherPartyLabel',
      );
    } catch (_) {
      // Sin bloquear la UX si notificaciones no estan disponibles.
    }
  }

  void dispose() {
    _messagesSub?.cancel();
  }
}
