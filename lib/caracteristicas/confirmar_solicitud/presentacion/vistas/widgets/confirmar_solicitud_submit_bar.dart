import 'package:flutter/material.dart';

import '../../../dominio/modelos/crear_solicitud_resultado.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'comentario_sheet.dart';
import 'tipo_vehiculo_sheet.dart';

/// Fila inferior de acciones: botón "Buscar conductor" y comentario — el
/// método de pago ya tiene su propia fila completa (`MetodoPagoCard`)
/// arriba, así que no se repite acá. [onSolicitudCreada] navega a la
/// pantalla de búsqueda — la vista es quien decide a dónde ir, esta fila
/// solo dispara la creación.
///
/// El tipo de vehículo ya no tiene su propio selector fijo en la pantalla:
/// "Buscar conductor" abre primero la modal de vehículo
/// (`mostrarTipoVehiculoSheet`) y solo sigue con la creación si el usuario
/// confirmó ahí — si cierra la modal sin confirmar, el tap completo se
/// cancela sin tocar Firestore.
class ConfirmarSolicitudSubmitBar extends StatelessWidget {
  const ConfirmarSolicitudSubmitBar({
    super.key,
    required this.onSolicitudCreada,
  });

  final ValueChanged<String> onSolicitudCreada;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final buttonHeight = ResponsiveHelper.hp(context, 6.5);

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: buttonHeight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colores.amarillo,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 2),
                  ),
                ),
              ),
              onPressed: vm.isSubmitting
                  ? null
                  : () async {
                      final confirmado = await mostrarTipoVehiculoSheet(
                        context,
                        vm,
                      );
                      if (confirmado != true || !context.mounted) return;

                      final messenger = ScaffoldMessenger.of(context);
                      final resultado = await vm.crearSolicitud();
                      if (!context.mounted) return;

                      switch (resultado) {
                        case SolicitudCreada(:final solicitudId):
                          onSolicitudCreada(solicitudId);
                        case SolicitudActivaExistente(:final solicitudId):
                          // Antes este caso era indistinguible del anterior:
                          // se descartaban en silencio el destino, precio,
                          // vehículo, método de pago y comentario recién
                          // elegidos, y se navegaba a la espera de un viaje
                          // distinto sin ninguna explicación.
                          final continuar = await _confirmarViajeEnCurso(
                            context,
                          );
                          if (continuar == true) {
                            onSolicitudCreada(solicitudId);
                          }
                        case CrearSolicitudFallo(:final motivo):
                          messenger.showSnackBar(
                            SnackBar(content: Text(motivo)),
                          );
                      }
                    },
              child: vm.isSubmitting
                  ? SizedBox(
                      width: ResponsiveHelper.wp(context, 5),
                      height: ResponsiveHelper.wp(context, 5),
                      child: const CircularProgressIndicator(
                        color: Colors.black87,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Buscar conductor',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.sp(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColores.textWhite,
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.wp(context, 2)),
        SizedBox(
          width: buttonHeight,
          height: buttonHeight,
          child: Tooltip(
            message: vm.comentario.isEmpty
                ? 'Sin comentario'
                : 'Comentario guardado',
            child: OutlinedButton(
              onPressed: () => mostrarComentarioSheet(context, vm),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 2),
                  ),
                ),
                side: const BorderSide(color: Colors.black26),
                foregroundColor: Colors.black87,
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                vm.comentario.isEmpty ? Icons.comment_outlined : Icons.comment,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Explica que ya hay un viaje en curso y deja elegir entre ir a verlo o
/// quedarse para cancelarlo primero.
Future<bool?> _confirmarViajeEnCurso(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ya tienes un viaje en curso'),
      content: const Text(
        'No se creó una solicitud nueva. Puedes ir a ver el viaje que ya '
        'tienes activo, o quedarte aquí y cancelarlo primero.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Quedarme aquí'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ver viaje activo'),
        ),
      ],
    ),
  );
}
