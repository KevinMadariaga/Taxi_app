import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

Future<void> mostrarMetodoPagoSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      void elegir(String metodo) {
        vm.setMetodoPago(metodo);
        Navigator.of(ctx).pop();
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TituloHoja(
                titulo: '¿Cómo vas a pagar?',
                subtitulo: 'Le pagas directamente al conductor al terminar.',
              ),
              const SizedBox(height: 18),
              _OpcionPago(
                icono: const Icon(
                  Icons.payments_rounded,
                  color: AppColores.success,
                  size: 24,
                ),
                fondoIcono: AppColores.success.withValues(alpha: 0.14),
                titulo: 'Efectivo',
                descripcion: 'Pagas en efectivo al llegar',
                seleccionado: vm.metodoPago == 'Efectivo',
                onTap: () => elegir('Efectivo'),
              ),
              const SizedBox(height: 10),
              _OpcionPago(
                icono: Image.asset(
                  'assets/img/nequi.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                ),
                // Logo con navy sólido: fondo blanco fijo en los dos temas.
                fondoIcono: Colors.white,
                titulo: 'Nequi',
                descripcion: 'Transfieres desde tu app de Nequi',
                seleccionado: vm.metodoPago == 'Nequi',
                onTap: () => elegir('Nequi'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _TituloHoja extends StatelessWidget {
  const _TituloHoja({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitulo,
          style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
        ),
      ],
    );
  }
}

class _OpcionPago extends StatelessWidget {
  const _OpcionPago({
    required this.icono,
    required this.fondoIcono,
    required this.titulo,
    required this.descripcion,
    required this.seleccionado,
    required this.onTap,
  });

  final Widget icono;
  final Color fondoIcono;
  final String titulo;
  final String descripcion;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: seleccionado
          ? Color.alphaBlend(
              AppColores.primary.withValues(alpha: 0.12),
              palette.surface,
            )
          : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: seleccionado ? AppColores.primary : palette.borderSubtle,
          width: seleccionado ? 1.8 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fondoIcono,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: icono,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descripcion,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  seleccionado
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  key: ValueKey(seleccionado),
                  color: seleccionado ? AppColores.primary : palette.grey400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
