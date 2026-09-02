import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../utils/moneda_format.dart';
import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

/// Modal de selección de vehículo: dos cuadros (Carro/Moto) lado a lado con
/// imagen + precio, y un botón "Confirmar vehículo" que aplica la elección.
/// Tocar un cuadro solo lo resalta (selección local, sin efecto todavía) —
/// hasta que se confirma no se toca `vm.tipoVehiculo`, así el usuario puede
/// comparar los dos precios antes de decidir.
///
/// Devuelve `true` si el usuario confirmó (y por lo tanto `vm.tipoVehiculo`
/// ya quedó actualizado); `false`/`null` si cerró sin confirmar (swipe,
/// tocar afuera) — quien llama debe tratar eso como cancelación, no seguir
/// con el resto del flujo.
Future<bool?> mostrarTipoVehiculoSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      VehicleType seleccionado = vm.tipoVehiculo;
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              12.w,
              0,
              12.w,
              MediaQuery.of(ctx).viewPadding.bottom + 12,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
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
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          'Tipo de vehículo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18.sp,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          'El precio varía según el vehículo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                      SizedBox(height: 18.h),
                      Row(
                        children: [
                          for (final tipo in VehicleType.values) ...[
                            Expanded(
                              child: _VehiculoCuadro(
                                tipo: tipo,
                                precio: vm.previsualizarValor(tipo),
                                isSelected: seleccionado == tipo,
                                onTap: () => setSheet(() => seleccionado = tipo),
                              ),
                            ),
                            if (tipo != VehicleType.values.last)
                              SizedBox(width: 12.w),
                          ],
                        ],
                      ),
                      SizedBox(height: 18.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colores.amarillo,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          onPressed: () {
                            vm.setTipoVehiculo(seleccionado);
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text(
                            'Confirmar vehículo',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColores.textWhite,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _VehiculoCuadro extends StatelessWidget {
  const _VehiculoCuadro({
    required this.tipo,
    required this.precio,
    required this.isSelected,
    required this.onTap,
  });

  final VehicleType tipo;
  final String precio;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicleAsset = tipo == VehicleType.moto
        ? 'assets/img/icono_moto.png'
        : 'assets/img/icono_carro.png';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 10.w),
        decoration: BoxDecoration(
          color: isSelected
              ? Colores.amarillo.withValues(alpha: 0.14)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? Colores.amarillo : Colors.black12,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colores.amarillo.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(vehicleAsset, height: 64.h, fit: BoxFit.contain),
            SizedBox(height: 10.h),
            Text(
              tipo.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.sp,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              '\$${formatCurrencyFromRaw(precio)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.sp,
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
