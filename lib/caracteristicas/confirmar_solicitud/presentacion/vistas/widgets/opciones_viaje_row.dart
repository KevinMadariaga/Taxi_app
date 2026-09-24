import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'comentario_sheet.dart';
import 'metodo_pago_sheet.dart';

/// Pago y nota para el conductor como dos pastillas lado a lado: cada una
/// muestra lo elegido y abre su selector.
class OpcionesViajeRow extends StatelessWidget {
  const OpcionesViajeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final esNequi = vm.metodoPago.toLowerCase().contains('nequi');
    final tieneNota = vm.comentario.trim().isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: _Pastilla(
            etiqueta: 'Pago',
            valor: vm.metodoPago,
            icono: esNequi
                ? Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      // Logo con navy sólido: fondo blanco fijo en los dos
                      // temas, como cualquier chip de marca.
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Image.asset(
                      'assets/img/nequi.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(
                    Icons.payments_rounded,
                    size: 20,
                    color: AppColores.success,
                  ),
            onTap: () => mostrarMetodoPagoSheet(context, vm),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Pastilla(
            etiqueta: 'Nota',
            valor: tieneNota ? vm.comentario.trim() : 'Agregar nota',
            icono: Icon(
              tieneNota ? Icons.sticky_note_2_rounded : Icons.edit_note_rounded,
              size: 21,
              color: tieneNota
                  ? AppColores.secondary
                  : context.palette.textSecondary,
            ),
            atenuado: !tieneNota,
            onTap: () => mostrarComentarioSheet(context, vm),
          ),
        ),
      ],
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    required this.onTap,
    this.atenuado = false,
  });

  final String etiqueta;
  final String valor;
  final Widget icono;
  final VoidCallback onTap;
  final bool atenuado;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              icono,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: palette.textSecondary,
                      ),
                    ),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: atenuado
                            ? palette.textSecondary
                            : palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
