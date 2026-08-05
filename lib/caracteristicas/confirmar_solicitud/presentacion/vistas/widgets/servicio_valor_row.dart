import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../utils/moneda_format.dart';
import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'tipo_vehiculo_sheet.dart';
import 'valor_servicio_sheet.dart';

/// Tarjeta "vehículo + valor": ícono + tipo de vehículo + distancia a la
/// izquierda, valor del servicio a la derecha. Tocar la tarjeta abre el
/// selector de tipo de vehículo (`mostrarTipoVehiculoSheet`); tocar el
/// valor en sí abre el editor de precio propuesto — dos zonas tappables
/// superpuestas, no una sola acción.
class ServicioValorRow extends StatelessWidget {
  const ServicioValorRow({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final esMoto = vm.tipoVehiculo == VehicleType.moto;
    final vehicleAsset = esMoto
        ? 'assets/img/icono_moto.png'
        : 'assets/img/icono_carro.png';
    final distanciaKm = vm.routeDistanceKm;

    final radius = BorderRadius.circular(ResponsiveHelper.wp(context, 4));
    return Material(
      color: AppColores.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => mostrarTipoVehiculoSheet(context, vm),
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 2),
            vertical: ResponsiveHelper.hp(context, 0.8),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: Colores.amarillo, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: ResponsiveHelper.wp(context, 11),
                height: ResponsiveHelper.wp(context, 11),
                padding: EdgeInsets.all(ResponsiveHelper.wp(context, 1.6)),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black),
                ),
                child: Image.asset(vehicleAsset, fit: BoxFit.contain),
              ),
              SizedBox(width: ResponsiveHelper.wp(context, 3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vm.tipoVehiculo.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: ResponsiveHelper.sp(context, 14),
                        color: AppColores.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (distanciaKm != null) ...[
                      SizedBox(height: ResponsiveHelper.hp(context, 0.3)),
                      Text(
                        '${distanciaKm.toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: ResponsiveHelper.sp(context, 12),
                          color: AppColores.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                onTap: () => mostrarValorServicioSheet(context, vm),
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.wp(context, 2),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.wp(context, 1),
                    vertical: ResponsiveHelper.hp(context, 0.6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sell, color: Colors.green, size: 18),
                      SizedBox(width: ResponsiveHelper.wp(context, 1)),
                      Text(
                        '\$${formatCurrencyFromRaw(vm.valorServicio)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: ResponsiveHelper.sp(context, 14),
                          color: AppColores.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColores.textSecondary,
                size: ResponsiveHelper.wp(context, 5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
