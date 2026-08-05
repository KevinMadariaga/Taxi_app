import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// El cliente confirma que va en camino al vehículo — enEspera→enCamino,
/// iniciado por el cliente (a diferencia de las demás transiciones de esta
/// fase, que las dispara el conductor).
class ConfirmarVoyEnCaminoUseCase {
  ConfirmarVoyEnCaminoUseCase(this._actualizarEstado);

  final ActualizarEstadoViajeUseCase _actualizarEstado;

  Future<void> call(String viajeId) {
    return _actualizarEstado(
      ActualizarEstadoViajeParams(
        viajeId: viajeId,
        estado: SolicitudEstado.enCamino,
      ),
    );
  }
}
