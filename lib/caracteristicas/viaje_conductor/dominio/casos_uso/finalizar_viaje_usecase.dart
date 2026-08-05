import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// enRuta→completado. `SolicitudFirestoreDatasource.actualizarEstado`
/// (detrás de `ActualizarEstadoViajeUseCase`) ya estampa `completedAt` +
/// `fecha de terminacion` con `serverTimestamp()` al detectar este estado —
/// no hace falta que este caso de uso lo repita.
class FinalizarViajeUseCase {
  FinalizarViajeUseCase(this._actualizarEstado);

  final ActualizarEstadoViajeUseCase _actualizarEstado;

  Future<void> call(String viajeId) {
    return _actualizarEstado(
      ActualizarEstadoViajeParams(
        viajeId: viajeId,
        estado: SolicitudEstado.completado,
      ),
    );
  }
}
