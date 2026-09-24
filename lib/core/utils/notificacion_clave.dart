/// Claves e ids de deduplicación de notificaciones — la mitad Dart de un
/// contrato que comparte con `functions/notificaciones.js`.
///
/// La app cancela una notificación por su id entero
/// (`NotificacionesServicio.cancel`), y para los avisos que llegan por FCM ese
/// id lo calcula el backend y viaja en `data.notifId`. Este módulo existe para
/// las notificaciones que la app arma por su cuenta, y para poder derivar el
/// mismo id cuando el backend no lo mandó (app nueva contra backend viejo).
///
/// **Si se cambia el algoritmo hay que cambiarlo en los dos lados.** Los
/// vectores están fijados en `test/notificacion_clave_test.dart` y en
/// `functions/notificaciones.test.js`: sin ellos, una divergencia no rompe
/// nada a la vista y se descubre en producción, con notificaciones imposibles
/// de retirar.
library;

/// Límite de `apns-collapse-id` según la documentación de APNs.
const int maxClaveBytes = 64;

/// Clave de deduplicación: `<tipo>_<entidad>`.
///
/// La entidad es lo que decide qué reemplaza a qué: para la solicitud entrante
/// es el `clienteId` (así el mismo cliente pidiendo varias veces ocupa una
/// sola entrada en la bandeja), para los avisos de un viaje el `solicitudId`.
String claveNotificacion(String tipo, [String? entidad]) {
  String limpia(String? v) =>
      (v ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  final base = limpia(tipo).isEmpty ? 'general' : limpia(tipo);
  final suf = limpia(entidad);
  final clave = suf.isEmpty ? base : '${base}_$suf';
  return clave.length <= maxClaveBytes
      ? clave
      : clave.substring(0, maxClaveBytes);
}

/// Id entero y estable para [clave], en `0..2^31-1`.
///
/// FNV-1a de 32 bits. No se usa `String.hashCode`: Dart no garantiza que sea
/// estable entre versiones del SDK, y el handler de background de FCM corre en
/// un isolate aparte.
///
/// Válido en Dart nativo (Android/iOS), donde los enteros son de 64 bits: el
/// producto intermedio llega a ~2^56 y no desborda. En **dart2js** los enteros
/// son doubles y pasando 2^53 perdería precisión, dando ids distintos a los
/// del backend. Esta app no corre en web; si alguna vez lo hace, hay que
/// pasar a `Math.imul`-equivalente (multiplicación por partes de 16 bits).
int idNotificacion(String clave) {
  var hash = 0x811c9dc5;
  for (final byte in clave.codeUnits) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  // A positivo: los ids de flutter_local_notifications son int32 con signo.
  return hash & 0x7fffffff;
}

/// Id de la notificación identificada por [tipo] y [entidad].
int idNotificacionDe(String tipo, [String? entidad]) =>
    idNotificacion(claveNotificacion(tipo, entidad));
