import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// enCamino→enRuta — GATEADO por el código de verificación: el conductor ya
/// no puede iniciar el tramo hacia el destino con un simple tap (como pasaba
/// antes en `beginTripAfterClientConfirm`), tiene que ingresar el código que
/// el cliente le dice de viva voz.
class IniciarRutaDestinoUseCase {
  IniciarRutaDestinoUseCase({
    required ActualizarEstadoViajeUseCase actualizarEstado,
    required ValidarCodigoVerificacionUseCase validarCodigo,
  }) : _actualizarEstado = actualizarEstado,
       _validarCodigo = validarCodigo;

  final ActualizarEstadoViajeUseCase _actualizarEstado;
  final ValidarCodigoVerificacionUseCase _validarCodigo;

  Future<ResultadoValidacionCodigo> call({
    required String viajeId,
    required String codigoIngresado,
  }) async {
    final resultado = await _validarCodigo(
      viajeId: viajeId,
      codigoIngresado: codigoIngresado,
    );

    if (resultado == ResultadoValidacionCodigo.correcto) {
      await _actualizarEstado(
        ActualizarEstadoViajeParams(
          viajeId: viajeId,
          estado: SolicitudEstado.enRuta,
        ),
      );
    }

    return resultado;
  }
}
