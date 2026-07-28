// Tests de caracterización de TripChatController (paso 4 del refactor de
// TripTrackingViewModel — ver graphify-out y trip_tracking_viewmodel_test.dart
// para el contexto completo).
//
// A diferencia del motor de movimiento, el chat no tiene historial de
// incidentes documentado — estos tests cierran la brecha de cobertura que
// quedó abierta al extraerlo (paso 4), no reconstruyen un caso de bug real.
//
// Fuera de alcance deliberado: la notificación local de mensaje nuevo
// (`_showMessageNotification`) usa el singleton real `NotificacionesServicio`
// (no se puede fakear: su constructor es privado a su propio archivo). La
// llamada está protegida por try/catch en el propio controller, así que en
// el entorno de test simplemente falla en silencio (MissingPluginException)
// sin afectar el resto del flujo — no se verifica que la notificación se
// muestre, solo que su fallo no rompe messages/unreadCount/onChanged.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/features/trip_tracking_cliente/controllers/trip_chat_controller.dart';
import 'package:taxi_app/features/trip_tracking_cliente/models/mensaje_model.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/local_cache_service.dart';

import 'test_helpers/trip_tracking_fakes.dart';

const _solicitudId = 'sol-1';
const _currentUserId = 'cliente-1';
const _otherUserId = 'conductor-1';

MensajeModel _mensaje({
  required String id,
  required String senderId,
  String texto = 'hola',
  Map<String, bool> readBy = const {},
}) {
  return MensajeModel(
    id: id,
    senderId: senderId,
    texto: texto,
    timestamp: DateTime.now(),
    readBy: readBy,
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condición no se cumplió dentro de $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<List<MensajeModel>> messagesController;
  late FakeChatService chatService;
  late TripChatController controller;
  late int onChangedCount;

  Future<void> setUpController() async {
    SharedPreferences.setMockInitialValues({});
    messagesController = StreamController<List<MensajeModel>>.broadcast();
    chatService = FakeChatService(messagesStream: messagesController.stream);
    onChangedCount = 0;

    controller = TripChatController(
      solicitudId: _solicitudId,
      currentUserId: _currentUserId,
      chatService: chatService,
      localCacheService: LocalCacheService(),
    );
    controller.onChanged = () => onChangedCount++;
  }

  tearDown(() async {
    controller.dispose();
    await messagesController.close();
  });

  group('restoreFromCache', () {
    setUp(setUpController);

    test('puebla messages/unreadCount desde cache local', () async {
      final cache = LocalCacheService();
      await cache.saveMessages(
        solicitudId: _solicitudId,
        messages: [
          _mensaje(id: 'm1', senderId: _otherUserId),
          _mensaje(id: 'm2', senderId: _currentUserId),
        ],
      );

      await controller.restoreFromCache();

      expect(controller.messages.length, 2);
      expect(controller.unreadCount, 1);
    });
  });

  group('bind() — primer batch (bootstrap)', () {
    setUp(setUpController);

    test('puebla messages/unreadCount, guarda en cache y notifica, sin romper por notificación', () async {
      controller.bind();

      messagesController.add([
        _mensaje(id: 'm1', senderId: _otherUserId),
      ]);

      await _pumpUntil(() => controller.messages.length == 1);

      expect(controller.unreadCount, 1);
      expect(onChangedCount, greaterThanOrEqualTo(1));

      final cache = LocalCacheService();
      final cached = await cache.readMessages(_solicitudId);
      expect(cached.length, 1);
    });
  });

  group('bind() — mensajes tras el bootstrap', () {
    setUp(setUpController);

    test('mensaje nuevo de otro usuario cuenta como no leído', () async {
      controller.bind();
      messagesController.add([_mensaje(id: 'm1', senderId: _otherUserId)]);
      await _pumpUntil(() => controller.messages.length == 1);

      messagesController.add([
        _mensaje(id: 'm1', senderId: _otherUserId),
        _mensaje(id: 'm2', senderId: _otherUserId),
      ]);
      await _pumpUntil(() => controller.messages.length == 2);

      expect(controller.unreadCount, 2);
    });

    test('mensaje nuevo propio no cuenta como no leído', () async {
      controller.bind();
      messagesController.add([_mensaje(id: 'm1', senderId: _otherUserId)]);
      await _pumpUntil(() => controller.messages.length == 1);

      messagesController.add([
        _mensaje(id: 'm1', senderId: _otherUserId),
        _mensaje(id: 'm2', senderId: _currentUserId),
      ]);
      await _pumpUntil(() => controller.messages.length == 2);

      expect(controller.unreadCount, 1);
    });
  });

  group('bind() — error en el stream', () {
    setUp(setUpController);

    test('cae a los mensajes cacheados', () async {
      final cache = LocalCacheService();
      await cache.saveMessages(
        solicitudId: _solicitudId,
        messages: [_mensaje(id: 'm1', senderId: _otherUserId)],
      );

      controller = TripChatController(
        solicitudId: _solicitudId,
        currentUserId: _currentUserId,
        chatService: chatService,
        localCacheService: cache,
      );
      controller.onChanged = () => onChangedCount++;
      controller.bind();

      messagesController.addError(StateError('firestore caído'));

      await _pumpUntil(() => controller.messages.isNotEmpty);
      expect(controller.messages.single.id, 'm1');
    });
  });

  group('sendMessage', () {
    setUp(setUpController);

    test('delega en ChatService con solicitudId/senderId/texto correctos', () async {
      await controller.sendMessage('hola conductor');

      expect(chatService.sendCount, 1);
      expect(chatService.lastSendSenderId, _currentUserId);
      expect(chatService.lastSendTexto, 'hola conductor');
    });
  });

  group('markAllAsRead', () {
    setUp(setUpController);

    test('no hace nada si no hay mensajes', () async {
      await controller.markAllAsRead();
      expect(chatService.markAllAsReadCount, 0);
    });

    test('delega en ChatService, marca localmente como leídos y deja unreadCount en 0', () async {
      controller.bind();
      messagesController.add([
        _mensaje(id: 'm1', senderId: _otherUserId),
        _mensaje(id: 'm2', senderId: _currentUserId),
      ]);
      await _pumpUntil(() => controller.messages.length == 2);
      expect(controller.unreadCount, 1);

      await controller.markAllAsRead();

      expect(chatService.markAllAsReadCount, 1);
      expect(controller.unreadCount, 0);
      final ajeno = controller.messages.firstWhere((m) => m.id == 'm1');
      expect(ajeno.isReadBy(_currentUserId), true);
    });
  });
}
