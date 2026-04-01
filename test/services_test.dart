import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/core/services/ubicacion_servicio.dart';

void main() {
  group('Servicios principales', () {
    test('AuthService puede instanciarse', () {
      final service = AuthService();
      expect(service, isNotNull);
    });
    /*test('ChatService puede instanciarse', () {
      final service = ChatService();
      expect(service, isNotNull);
    });*/
    /*test('FirebaseService puede instanciarse', () {
      final service = FirebaseService();
      expect(service, isNotNull);
    });*/
    test('MapService puede instanciarse', () {
      final service = MapService();
      expect(service, isNotNull);
    });
    test('NotificacionesServicio puede instanciarse', () {
      final service = NotificacionesServicio.instance;
      expect(service, isNotNull);
    });
    test('RouteCacheService puede instanciarse', () {
      final service = RouteCacheService();
      expect(service, isNotNull);
    });
    /*test('TrackingService puede instanciarse', () {
      final service = TrackingService();
      expect(service, isNotNull);
    });*/
    test('UbicacionService puede instanciarse', () {
      final service = UbicacionService();
      expect(service, isNotNull);
    });
  });
}
