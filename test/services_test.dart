import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/services/auth_service.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/map_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/notification_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:taxi_app/services/ubicacion_servicio.dart';

void main() {
  group('Servicios principales', () {
    test('AuthService puede instanciarse', () {
      final service = AuthService();
      expect(service, isNotNull);
    });
    test('ChatService puede instanciarse', () {
      final service = ChatService();
      expect(service, isNotNull);
    });
    test('FirebaseService puede instanciarse', () {
      final service = FirebaseService();
      expect(service, isNotNull);
    });
    test('MapService puede instanciarse', () {
      final service = MapService();
      expect(service, isNotNull);
    });
    test('NotificacionesServicio puede instanciarse', () {
      final service = NotificacionesServicio.instance;
      expect(service, isNotNull);
    });
    test('NotificationService puede instanciarse', () {
      final service = NotificationService.instance;
      expect(service, isNotNull);
    });
    test('RouteCacheService puede instanciarse', () {
      final service = RouteCacheService();
      expect(service, isNotNull);
    });
    test('TrackingService puede instanciarse', () {
      final service = TrackingService();
      expect(service, isNotNull);
    });
    test('UbicacionService puede instanciarse', () {
      final service = UbicacionService();
      expect(service, isNotNull);
    });
  });
}
