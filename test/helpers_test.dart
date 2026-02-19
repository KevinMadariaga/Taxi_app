import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/helper/firebase_helper.dart';
import 'package:taxi_app/helper/map_helper.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';

void main() {
  group('Helpers', () {
    test('FirebaseHelper tiene método estático', () {
      expect(FirebaseHelper.initializeFirebase, isA<Function>());
    });
    test('MapHelper tiene método estático', () {
      expect(MapHelper.loadMarkerIcon, isA<Function>());
    });
    test('PermissionsHelper tiene método estático', () {
      expect(PermissionsHelper.isLocationServiceEnabled, isA<Function>());
    });
    test('ResponsiveHelper tiene método estático', () {
      expect(ResponsiveHelper.getResponsiveData, isA<Function>());
    });
    test('SessionHelper tiene método estático', () {
      expect(SessionHelper.saveSession, isA<Function>());
    });
  });
}
