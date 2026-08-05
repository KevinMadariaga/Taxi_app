import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'comentario_sheet.dart';

/// Fila inferior de acciones: botón "Buscar conductor" y comentario — el
/// método de pago ya tiene su propia fila completa (`MetodoPagoCard`)
/// arriba, así que no se repite acá. [onSolicitudCreada] navega a la
/// pantalla de búsqueda — la vista es quien decide a dónde ir, esta fila
/// solo dispara la creación.
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
                      final messenger = ScaffoldMessenger.of(context);
                      final solicitudId = await vm.crearSolicitud();
                      if (!context.mounted) return;
                      if (solicitudId != null) {
                        onSolicitudCreada(solicitudId);
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Error al crear la solicitud'),
                          ),
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
