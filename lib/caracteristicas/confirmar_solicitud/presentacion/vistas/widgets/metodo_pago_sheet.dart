import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

Future<void> mostrarMetodoPagoSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final bottomGap = media.viewPadding.bottom + 12;

      return Padding(
        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, bottomGap),
        child: Material(
          color: AppColores.surface,
          borderRadius: BorderRadius.circular(20.r),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 16.h),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Método de pago',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18.sp,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Seleccionado: ${vm.metodoPago}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                  SizedBox(height: 18.h),
                  _MetodoPagoOpcion(
                    icono: const Icon(Icons.payments_outlined, size: 26),
                    label: 'Efectivo',
                    isSelected: vm.metodoPago == 'Efectivo',
                    onTap: () {
                      vm.setMetodoPago('Efectivo');
                      Navigator.of(ctx).pop();
                    },
                  ),
                  SizedBox(height: 12.h),
                  _MetodoPagoOpcion(
                    icono: Image.asset(
                      'assets/img/nequi.png',
                      width: 26.w,
                      height: 26.h,
                      fit: BoxFit.contain,
                    ),
                    label: 'Nequi',
                    isSelected: vm.metodoPago == 'Nequi',
                    onTap: () {
                      vm.setMetodoPago('Nequi');
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _MetodoPagoOpcion extends StatelessWidget {
  const _MetodoPagoOpcion({
    required this.icono,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Widget icono;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColores.primary.withValues(alpha: 0.14)
              : AppColores.background,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? AppColores.primary : AppColores.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icono,
            SizedBox(width: 10.w),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.sp,
                color: AppColores.textPrimary,
              ),
            ),
            if (isSelected) ...[
              SizedBox(width: 10.w),
              Icon(Icons.check_circle, color: AppColores.primary, size: 20.sp),
            ],
          ],
        ),
      ),
    );
  }
}
