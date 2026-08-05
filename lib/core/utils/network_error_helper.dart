import 'dart:async';
import 'dart:io';

/// Detecta si una excepción representa falta de conexión a internet (no un
/// error de negocio/configuración), para poder mostrarle al usuario un
/// mensaje claro ("no tienes conexión") en vez del texto crudo de la
/// excepción original.
bool esErrorDeConexion(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final texto = error.toString().toLowerCase();
  return texto.contains('socketexception') ||
      texto.contains('failed host lookup') ||
      texto.contains('network is unreachable') ||
      texto.contains('no address associated with hostname') ||
      texto.contains('connection timed out') ||
      texto.contains('connection reset') ||
      texto.contains('network_error');
}
