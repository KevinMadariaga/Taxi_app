import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

/// Snapshot inmutable de lo que el cliente confirmó en pantalla, listo para
/// que [CrearSolicitudUseCase] lo procese. El ViewModel arma uno de estos a
/// partir de su estado justo antes de crear la solicitud — así el caso de
/// uso no depende de `ChangeNotifier` ni de ningún estado mutable.
class SolicitudBorrador {
  const SolicitudBorrador({
    required this.origen,
    required this.destino,
    required this.tipoVehiculo,
    required this.metodoPago,
    required this.comentario,
    required this.valorServicio,
  });

  final LocationModel origen;
  final LocationModel destino;
  final VehicleType tipoVehiculo;
  final String metodoPago;
  final String comentario;

  /// Texto crudo del input (solo dígitos + posibles separadores de miles);
  /// el caso de uso lo parsea a número al construir la solicitud.
  final String valorServicio;
}
