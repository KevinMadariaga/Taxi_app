import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/constants/canales_notificacion.dart';

void main() {
  test('cada evento cae en su canal, igual que en el backend', () {
    final para = CanalesNotificacion.para;
    expect(para('nueva_solicitud'), CanalesNotificacion.solicitudes);
    expect(para('conductor_cerca'), CanalesNotificacion.estadoViaje);
    expect(para('contraoferta'), CanalesNotificacion.estadoViaje);
    for (final e in [
      'buscando',
      'asignado',
      'en espera',
      'en camino',
      'en ruta',
      'completado',
    ]) {
      expect(
        para('trip_status_change', estado: e),
        CanalesNotificacion.estadoViaje,
        reason: e,
      );
    }
    for (final e in ['cancelado', 'sin respuesta']) {
      expect(
        para('trip_status_change', estado: e),
        CanalesNotificacion.cancelado,
        reason: e,
      );
    }
    for (final t in [
      'trip_chat_message',
      'soporte_chat',
      'soporte_chat_respuesta',
    ]) {
      expect(para(t), CanalesNotificacion.mensajes, reason: t);
    }
    expect(para('promo'), CanalesNotificacion.promociones);
    for (final t in [
      'membresia_activada',
      'payment_method_change',
      'reporte',
      'solicitud_activa',
    ]) {
      expect(para(t), CanalesNotificacion.avisos, reason: t);
    }
    expect(para('emergencia'), isNull);
  });

  test('ids y sonidos coinciden con functions/notificaciones.js', () {
    final js = File('functions/notificaciones.js').readAsStringSync();
    for (final c in CanalesNotificacion.todos) {
      expect(js, contains('id: "${c.id}"'), reason: c.id);
      if (c.sonido != null) {
        expect(js, contains('sonido: "${c.sonido}"'), reason: c.id);
      }
    }
  });

  test('los audios están en Android (protegidos del shrink) y en iOS', () {
    final keep = File(
      'android/app/src/main/res/raw/keep.xml',
    ).readAsStringSync();
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    for (final c in CanalesNotificacion.todos.where((c) => c.sonido != null)) {
      final s = c.sonido!;
      expect(
        File('android/app/src/main/res/raw/$s.mp3').existsSync(),
        isTrue,
        reason: s,
      );
      expect(keep, contains('@raw/$s'), reason: s);
      expect(File('ios/Runner/Sonidos/$s.caf').existsSync(), isTrue);
      expect(pbx, contains('$s.caf in Resources'), reason: s);
      // Android exige minúsculas, sin espacios ni guiones.
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(s), isTrue, reason: s);
    }
  });
}
