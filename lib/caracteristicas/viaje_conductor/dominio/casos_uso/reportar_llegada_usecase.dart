import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// El conductor confirma que llegó al punto de recogida (asignado→enEspera)
/// y, en el mismo paso, genera el código de verificación que el cliente
/// verá en pantalla — la generación queda atada a este momento porque es
/// la primera vez que conductor y cliente están físicamente co-ubicados.
class ReportarLlegadaUseCase {
  ReportarLlegadaUseCase({
    required ActualizarEstadoViajeUseCase actualizarEstado,
    required GenerarCodigoVerificacionUseCase generarCodigo,
  }) : _actualizarEstado = actualizarEstado,
       _generarCodigo = generarCodigo;

  final ActualizarEstadoViajeUseCase _actualizarEstado;
  final GenerarCodigoVerificacionUseCase _generarCodigo;

  Future<void> call(String viajeId) async {
    await _actualizarEstado(
      ActualizarEstadoViajeParams(
        viajeId: viajeId,
        estado: SolicitudEstado.enEspera,
      ),
    );
    await _generarCodigo(viajeId);
  }
}
