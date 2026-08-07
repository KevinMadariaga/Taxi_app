import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Muestra el código de 4 dígitos que el conductor generó al llegar —
/// visible desde que se genera hasta que se valida (el conductor lo pide
/// de viva voz).
///
/// Puramente presentacional: recibe el [codigo] ya resuelto. Antes tenía su
/// propio `StreamBuilder`, pero `ViajeClienteScreen` necesita saber si el
/// banner está visible para agrandar la tarjeta mientras el código se muestra
/// — con el stream acá dentro esa información no salía del widget. El stream
/// vive ahora en la pantalla ([CodigoVerificacionBanner.esVisible] decide el
/// resto), así que sigue habiendo un solo listener sobre el documento.
///
/// Distribución tipo banner (etiqueta a la izquierda, 4 casillas
/// individuales a la derecha) en vez de un solo bloque de texto grande.
class CodigoVerificacionBanner extends StatelessWidget {
  const CodigoVerificacionBanner({super.key, required this.codigo});

  final CodigoVerificacionEntity? codigo;

  /// El banner ocupa espacio solo entre que el código se genera y se valida.
  static bool esVisible(CodigoVerificacionEntity? codigo) =>
      codigo != null && codigo.generado && !codigo.validado;

  @override
  Widget build(BuildContext context) {
    final codigo = this.codigo;
    if (!esVisible(codigo)) return const SizedBox.shrink();

    final digitos = codigo!.codigo.split('');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColores.brand50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Código PIN de esta solicitud',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColores.brand900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < digitos.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Container(
                  width: 30,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColores.brand200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    digitos[i],
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColores.brand900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
