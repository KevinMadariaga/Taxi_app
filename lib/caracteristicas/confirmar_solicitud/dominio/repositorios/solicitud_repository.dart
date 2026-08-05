import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../entidades/cliente_actual.dart';

/// Contrato de persistencia de solicitudes de viaje. La implementación es
/// la única que conoce la forma del documento de Firestore — el caso de uso
/// solo habla en términos de dominio (cliente, ubicaciones, tarifa).
abstract class SolicitudRepository {
  /// Id de la solicitud activa más reciente del cliente, o `null` si no
  /// tiene ninguna en curso.
  Future<String?> buscarActivaDeCliente(String clienteId);

  /// Crea la solicitud y devuelve su id.
  Future<String> crear({
    required ClienteActual cliente,
    required LocationModel origen,
    required String origenDireccion,
    required LocationModel destino,
    required String destinoDireccion,
    required VehicleType tipoVehiculo,
    required String metodoPago,
    required String comentario,
    required double valorServicio,
  });
}
