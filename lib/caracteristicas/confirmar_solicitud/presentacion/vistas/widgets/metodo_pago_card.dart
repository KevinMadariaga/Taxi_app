import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'metodo_pago_sheet.dart';

/// Fila "Método de pago": ícono + método seleccionado + flecha — toda la
/// fila abre el selector de método de pago al tocarla.
class MetodoPagoCard extends StatelessWidget {
  const MetodoPagoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final esNequi = vm.metodoPago.toLowerCase().contains('nequi');

    final radius = BorderRadius.circular(ResponsiveHelper.wp(context, 4));
    return Material(
      color: AppColores.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => mostrarMetodoPagoSheet(context, vm),
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 2),
            vertical: ResponsiveHelper.hp(context, 0.9),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColores.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.wp(context, 1.6)),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 3),
                  ),
                ),
                child: esNequi
                    ? Image.asset(
                        'assets/img/nequi.png',
                        width: ResponsiveHelper.wp(context, 5.5),
                        height: ResponsiveHelper.wp(context, 5.5),
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.money, color: Colors.green),
              ),
              SizedBox(width: ResponsiveHelper.wp(context, 3)),
              Expanded(
                child: Text(
                  vm.metodoPago,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: ResponsiveHelper.sp(context, 14),
                    color: AppColores.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: AppColores.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
