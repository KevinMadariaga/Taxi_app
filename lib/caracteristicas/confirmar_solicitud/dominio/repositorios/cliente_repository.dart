import '../entidades/cliente_actual.dart';

/// Contrato de acceso a los datos del cliente autenticado. Ninguna clase de
/// dominio/presentación debe llamar a `FirebaseAuth`/`FirebaseFirestore`
/// directo para esto — solo a esta interfaz.
abstract class ClienteRepository {
  /// `null` si no hay usuario autenticado.
  Future<ClienteActual?> obtenerActual();
}
