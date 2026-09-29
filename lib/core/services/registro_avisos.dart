import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Eventos que ya avisaron hace poco, compartido entre isolates: el handler
/// de background de FCM corre en uno aparte, así que la memoria no sirve y se
/// usa SharedPreferences (con `reload()` para ver lo que escribió el otro).
///
/// El primero que "reclama" un evento lo muestra; los demás lo descartan
/// durante [ventana]. Pasada la ventana la entrada se limpia sola.
class RegistroAvisos {
  RegistroAvisos._();

  static const String _clave = 'avisos_push_mostrados';
  static const Duration ventana = Duration(minutes: 3);

  /// `true` si [evento] no se avisó en la [ventana] (y queda reclamado).
  static Future<bool> reclamar(String evento, {DateTime? ahora}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final t = (ahora ?? DateTime.now()).millisecondsSinceEpoch;

    Map<String, dynamic> vistos;
    try {
      vistos = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(_clave) ?? '{}') as Map,
      );
    } catch (_) {
      vistos = {};
    }
    vistos.removeWhere((_, v) => v is! int || t - v > ventana.inMilliseconds);

    final libre = !vistos.containsKey(evento);
    if (libre) vistos[evento] = t;
    await prefs.setString(_clave, jsonEncode(vistos));
    return libre;
  }
}
