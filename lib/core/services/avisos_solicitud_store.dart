import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi_app/core/utils/error_reporter.dart';

/// Qué avisos de "Solicitud entrante" hay mostrados ahora mismo en la bandeja
/// del conductor, por `clienteId`.
///
/// Existe porque la red de seguridad tiene que sobrevivir al proceso. El push
/// silencioso de retirada (`onSolicitudDejaDeBuscar`) no llega si el conductor
/// forzó el cierre de la app, y ese es justamente el caso en el que el aviso
/// se queda invitando a un viaje que ya no existe. Al reabrir, la lista de
/// solicitudes se reconstruye desde Firestore, pero la memoria de qué se había
/// mostrado arrancaba vacía: no había con qué comparar, así que no se
/// cancelaba nada. Esto persiste esa memoria.
///
/// Se escribe desde el handler de FCM —incluido el isolate de background, de
/// ahí que no haya estado en memoria: cada operación relee— y se consume en
/// `PendingSolicitudesController`.
class AvisosSolicitudStore {
  const AvisosSolicitudStore._();

  static const String _clave = 'avisos_solicitud_mostrados';

  /// Cota para que un token que quede huérfano no haga crecer la lista sin
  /// fin. 40 es holgado: son clientes con una solicitud viva a la vez.
  static const int _maxEntradas = 40;

  static Future<Set<String>> mostrados() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_clave) ?? const <String>[]).toSet();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AvisosSolicitudStore');
      return <String>{};
    }
  }

  static Future<void> registrar(String clienteId) async {
    if (clienteId.isEmpty) return;
    await _actualizar((actuales) {
      actuales
        ..remove(clienteId)
        ..add(clienteId);
      while (actuales.length > _maxEntradas) {
        actuales.removeAt(0);
      }
    });
  }

  static Future<void> olvidar(Iterable<String> clienteIds) async {
    final aBorrar = clienteIds.where((c) => c.isNotEmpty).toSet();
    if (aBorrar.isEmpty) return;
    await _actualizar((actuales) => actuales.removeWhere(aBorrar.contains));
  }

  static Future<void> limpiar() => _actualizar((actuales) => actuales.clear());

  static Future<void> _actualizar(void Function(List<String>) cambio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final actuales = [...(prefs.getStringList(_clave) ?? const <String>[])];
      cambio(actuales);
      await prefs.setStringList(_clave, actuales);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AvisosSolicitudStore');
    }
  }
}
