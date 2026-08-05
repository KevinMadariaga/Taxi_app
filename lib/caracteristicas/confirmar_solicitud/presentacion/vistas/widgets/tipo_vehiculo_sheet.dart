import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../utils/moneda_format.dart';
import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

Future<void> mostrarTipoVehiculoSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      VehicleType selected = vm.tipoVehiculo;
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              12.w,
              0,
              12.w,
              MediaQuery.of(ctx).viewPadding.bottom + 12,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20.r),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 24.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        margin: EdgeInsets.only(bottom: 16.h),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),
                    Text(
                      'Tipo de vehículo',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18.sp,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'El precio varía según el vehículo',
                      style: TextStyle(color: Colors.black54, fontSize: 13.sp),
                    ),
                    SizedBox(height: 16.h),
                    ...VehicleType.values.map((tipo) {
                      final isSelected = selected == tipo;
                      final vehicleAsset = tipo == VehicleType.moto
                          ? 'assets/img/icono_moto.png'
                          : 'assets/img/icono_carro.png';
                      return Padding(
                        padding: EdgeInsets.only(bottom: 10.h),
                        child: GestureDetector(
                          onTap: () {
                            setSheet(() => selected = tipo);
                            vm.setTipoVehiculo(tipo);
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () {
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                              },
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 12.h,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colores.amarillo.withValues(alpha: 0.14)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: isSelected
                                    ? Colores.amarillo
                                    : Colors.black12,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colores.amarillo.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44.w,
                                  height: 44.w,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colores.amarillo
                                          : Colors.black12,
                                    ),
                                  ),
                                  padding: EdgeInsets.all(8.w),
                                  child: Image.asset(
                                    vehicleAsset,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                SizedBox(width: 14.w),
                                Expanded(
                                  child: Text(
                                    tipo.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16.sp,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.sell,
                                  color: Colors.green,
                                  size: 15,
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  '\$${formatCurrencyFromRaw(vm.previsualizarValor(tipo))}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.sp,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
