import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/helper/session_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Session logout cleanup', () {
    test('clearSession removes auth and trip cache keys', () async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'administrador',
        'user_uid': '',
        'cached_user_name': 'Kevin',
        'active_solicitud_id': 'sol_123',
        'conductor_solicitud_activa': 'sol_123',
        'cliente_solicitud_activa': 'sol_123',
        'route_cache_sol_123': '{"a":1}',
        'trip_cache_route_sol_123': '{"a":1}',
        'trip_cache_messages_sol_123': '[1,2,3]',
        'solicitud_progreso_sol_123': 'in_progress',
        'keep_me': 'should_stay',
      });

      final before = await SharedPreferences.getInstance();
      expect(before.getBool('is_logged_in'), isTrue);
      expect(before.getString('active_solicitud_id'), isNotNull);

      await SessionHelper.clearSession();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isNull);
      expect(prefs.getString('user_role'), isNull);
      expect(prefs.getString('user_uid'), isNull);
      expect(prefs.getString('cached_user_name'), isNull);
      expect(prefs.getString('active_solicitud_id'), isNull);
      expect(prefs.getString('conductor_solicitud_activa'), isNull);
      expect(prefs.getString('cliente_solicitud_activa'), isNull);
      expect(prefs.getString('route_cache_sol_123'), isNull);
      expect(prefs.getString('trip_cache_route_sol_123'), isNull);
      expect(prefs.getString('trip_cache_messages_sol_123'), isNull);
      expect(prefs.getString('solicitud_progreso_sol_123'), isNull);

      // Unrelated preference should remain untouched.
      expect(prefs.getString('keep_me'), equals('should_stay'));
    });
  });
}
