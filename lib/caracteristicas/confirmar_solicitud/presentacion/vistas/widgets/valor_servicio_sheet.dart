import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';

import '../../utils/moneda_format.dart';
import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

Future<void> mostrarValorServicioSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) async {
  final initialDigits = vm.valorServicio.replaceAll(RegExp(r'[^0-9]'), '');
  String formatInput(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final parsed = int.tryParse(digits) ?? 0;
    return formatCurrency(parsed);
  }

  final controller = TextEditingController(text: formatInput(initialDigits))
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: formatInput(initialDigits).length,
    );
  final focusNode = FocusNode();
  bool isFormatting = false;

  void guardar(BuildContext ctx) {
    final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) vm.setValorServicio(digits);
    Navigator.of(ctx).pop();
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, _) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final safePad = MediaQuery.of(ctx).viewPadding.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              12.w,
              16.h,
              12.w,
              bottomInset > 0 ? bottomInset + 8 : safePad + 12,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿Cuánto ofreces por el servicio?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18.sp,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: false,
                        signed: false,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        if (isFormatting) return;
                        final formatted = formatInput(value);
                        if (formatted == value) return;
                        isFormatting = true;
                        controller.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                        isFormatting = false;
                      },
                      onSubmitted: (_) => guardar(ctx),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        hintText: 'Ej: ${vm.tipoVehiculo.basePriceDia}',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colores.amarillo,
                            width: 2.w,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colores.amarillo,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        onPressed: () => guardar(ctx),
                        child: const Text(
                          'Guardar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  controller.dispose();
  focusNode.dispose();
}
