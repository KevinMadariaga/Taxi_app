import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/mensaje_model.dart';
import '../services/chat_service.dart';
import '../services/local_cache_service.dart';

/// Chat del viaje: binding a Firestore, cache local, conteo de no leídos y
/// notificación local de mensajes nuevos.
///
/// Extraído de `TripTrackingViewModel` — sin historial de incidentes (a
/// diferencia del motor de movimiento), pero mezclado en la misma clase de
/// ~1000 líneas sin relación con tracking GPS/ruta. Mismo patrón de
/// `SolicitudEstadoController`: clase plana con sus propios callbacks, sin
/// heredar `ChangeNotifier`.
class TripChatController {
  TripChatController({
    required this.solicitudId,
    required this.currentUserId,
    ChatService? chatService,
    LocalCacheService? localCacheService,
    NotificacionesServicio? notificationService,
  }) : _chatService = chatService ?? ChatService(),
       _localCacheService = localCacheService ?? LocalCacheService(),
       _notificationService = notificationService ?? NotificacionesServicio.instance;

  final String solicitudId;
  final String currentUserId;

  final ChatService _chatService;
  final LocalCacheService _localCacheService;
  final NotificacionesServicio _notificationService;

  List<MensajeModel> messages = const [];
  int unreadCount = 0;

  StreamSubscription<List<MensajeModel>>? _messagesSub;
  bool _bootstrapped = false;

  /// Se dispara cada vez que cambian `messages`/`unreadCount` (nuevo batch
  /// del stream, o `markAllAsRead`). El viewmodel lo usa para su propio
  /// notify pesado (Scaffold/Card).
  VoidCallback? onChanged;

  Future<void> restoreFromCache() async {
    final cached = await _localCacheService.readMessages(solicitudId);
    if (cached.isNotEmpty) {
      messages = cached;
      _computeUnreadCount();
    }
  }

  void bind() {
    _messagesSub?.cancel();
    _messagesSub = _chatService
        .watchMessages(solicitudId)
        .listen(
          (incoming) async {
            if (_bootstrapped) {
              final previousIds = messages.map((m) => m.id).toSet();
              final newIncoming = incoming.where(
                (m) =>
                    !previousIds.contains(m.id) && m.senderId != currentUserId,
              );

              for (final item in newIncoming) {
                await _showMessageNotification(item.texto);
              }
            } else {
              _bootstrapped = true;
            }

            messages = incoming;
            _computeUnreadCount();

            await _localCacheService.saveMessages(
              solicitudId: solicitudId,
              messages: incoming,
            );

            onChanged?.call();
          },
          onError: (error) async {
            final cachedMessages = await _localCacheService.readMessages(
              solicitudId,
            );
            if (cachedMessages.isNotEmpty) {
              messages = cachedMessages;
              _computeUnreadCount();
              onChanged?.call();
            }
          },
        );
  }

  Future<void> sendMessage(String text) {
    return _chatService.sendMessage(
      solicitudId: solicitudId,
      senderId: currentUserId,
      texto: text,
    );
  }

  Future<void> markAllAsRead() async {
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
        senderName: '\u{1F4AC} Nuevo mensaje del conductor',
        message: body,
      );
    } catch (_) {
      // Sin bloquear la UX si notificaciones no estan disponibles.
    }
  }

  void dispose() {
    _messagesSub?.cancel();
  }
}
