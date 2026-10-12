import 'package:firebase_core/firebase_core.dart';

/// Texto para el admin cuando guardar/enviar/borrar falla: distingue un
/// permiso negado (reglas, rol) de un problema de red, en vez de culpar
/// siempre a la conexión.
String mensajeErrorAccion(Object error, {String accion = 'guardar'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'No tienes permiso para $accion esto. Verifica que tu cuenta '
            'sea de administrador.';
      case 'resource-exhausted':
        // El servidor ya explica el límite y cuándo reintentar.
        return error.message ?? 'Llegaste al límite. Inténtalo más tarde.';
      case 'not-found':
        return 'Ya no existe: puede que otro admin lo haya borrado.';
      case 'unavailable':
      case 'deadline-exceeded':
        break;
      default:
        return 'No se pudo $accion (${error.code}). Inténtalo de nuevo.';
    }
  }
  return 'No se pudo $accion. Revisa tu conexión e inténtalo de nuevo.';
}
