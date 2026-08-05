import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
      final bottomGap = media.viewPadding.bottom + 10;

      return Padding(
        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, bottomGap),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text(
                    'Método de pago',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Seleccionado: ${vm.metodoPago}'),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Efectivo'),
                  selected: vm.metodoPago == 'Efectivo',
                  trailing: vm.metodoPago == 'Efectivo'
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () {
                    vm.setMetodoPago('Efectivo');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: Image.asset(
                    'assets/img/nequi.png',
                    width: 28.w,
                    height: 28.h,
                    fit: BoxFit.cover,
                  ),
                  title: const Text('Nequi'),
                  selected: vm.metodoPago == 'Nequi',
                  trailing: vm.metodoPago == 'Nequi'
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () {
                    vm.setMetodoPago('Nequi');
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
