import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/services/bandeja_notificaciones.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> guardar(String id, {String tipo = 'promo'}) =>
      BandejaNotificaciones.guardar(
        id: id,
        titulo: 'Título $id',
        cuerpo: 'Cuerpo',
        tipo: tipo,
      );

  test(
    'cuenta no leídas, no duplica el mismo mensaje y marca leídas',
    () async {
      final bandeja = BandejaNotificaciones.instance;
      await guardar('a');
      await guardar('b');
      await guardar('a'); // mismo push visto al llegar y al tocarlo
      await bandeja.cargar();
      expect(bandeja.avisos.value.map((a) => a.id), ['b', 'a']);
      expect(bandeja.noLeidos, 2);

      await bandeja.marcarTodasLeidas();
      await bandeja.cargar();
      expect(bandeja.noLeidos, 0);
    },
  );

  test('ignora retiros y avisos vacíos; guarda como máximo 50', () async {
    final bandeja = BandejaNotificaciones.instance;
    await guardar('r', tipo: 'retirar_notificacion');
    await BandejaNotificaciones.guardar(
      id: 'v',
      titulo: ' ',
      cuerpo: '',
      tipo: 'promo',
    );
    for (var i = 0; i < 55; i++) {
      await guardar('$i');
    }
    await bandeja.cargar();
    expect(bandeja.avisos.value.length, 50);
    expect(bandeja.avisos.value.first.id, '54');
    expect(bandeja.avisos.value.any((a) => a.id == 'r' || a.id == 'v'), false);
  });

  test('solo guarda soporte, reportes y promociones', () async {
    final bandeja = BandejaNotificaciones.instance;
    for (final tipo in [
      'nueva_solicitud',
      'trip_status_change',
      'trip_chat_message',
      'conductor_cerca',
      'membresia_activada',
    ]) {
      await guardar(tipo, tipo: tipo);
    }
    for (final tipo in [
      'soporte_chat_respuesta',
      'soporte_chat',
      'reporte',
      'promo',
    ]) {
      await guardar(tipo, tipo: tipo);
    }
    await bandeja.cargar();
    expect(bandeja.avisos.value.map((a) => a.tipo).toSet(), {
      'soporte_chat_respuesta',
      'soporte_chat',
      'reporte',
      'promo',
    });
  });

  test('lo guardado antes del filtro deja de verse', () async {
    SharedPreferences.setMockInitialValues({
      'bandeja_notificaciones':
          '[{"id":"x","titulo":"Viaje","cuerpo":"c","tipo":"trip_status_change",'
          '"fecha":0},{"id":"p","titulo":"Promo","cuerpo":"c","tipo":"promo",'
          '"fecha":0}]',
    });
    final bandeja = BandejaNotificaciones.instance;
    await bandeja.cargar();
    expect(bandeja.avisos.value.map((a) => a.id), ['p']);
  });
}
