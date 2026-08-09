import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// El conductor confirma que llegó al punto de recogida (asignado→enEspera)
/// y, en el mismo paso, genera el código de verificación que el cliente
/// verá en pantalla — la generación queda atada a este momento porque es
/// la primera vez que conductor y cliente están físicamente co-ubicados.
///
/// **El código se genera ANTES de mover el estado**, y el orden importa:
/// son dos escrituras separadas sobre el mismo documento y no hay
/// transacción. Con el orden inverso, si fallaba la generación el viaje
/// quedaba en `en espera` sin código — y ahí la tarjeta muestra "Esperando
/// confirmación..." deshabilitado, sin ninguna forma de reintentar, hasta
/// que expira el plazo y se cancela por `sin respuesta`. Generando primero,
/// un fallo deja el viaje en `asignado` con el botón "Ya llegué al punto"
/// todavía activo: el conductor reintenta y listo. El caso inverso (código
/// generado y estado sin mover) es inocuo: `GenerarCodigoVerificacionUseCase`
/// es idempotente y reusa el código ya generado.
class ReportarLlegadaUseCase {
  ReportarLlegadaUseCase({
    required ActualizarEstadoViajeUseCase actualizarEstado,
    required GenerarCodigoVerificacionUseCase generarCodigo,
  }) : _actualizarEstado = actualizarEstado,
       _generarCodigo = generarCodigo;

  final ActualizarEstadoViajeUseCase _actualizarEstado;
  final GenerarCodigoVerificacionUseCase _generarCodigo;

  Future<void> call(String viajeId) async {
    await _generarCodigo(viajeId);
    await _actualizarEstado(
      ActualizarEstadoViajeParams(
        viajeId: viajeId,
        estado: SolicitudEstado.enEspera,
      ),
    );
  }
}
