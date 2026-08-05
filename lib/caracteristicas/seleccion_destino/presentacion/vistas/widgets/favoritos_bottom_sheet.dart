import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';

import '../../../dominio/entidades/ubicacion_entity.dart';
import '../../viewmodels/seleccion_destino_viewmodel.dart';

/// Lista de favoritos guardados. Tocar uno lo devuelve al caller (que llena
/// el campo destino) — no navega a ningún lado por sí solo.
Future<UbicacionEntity?> mostrarFavoritosBottomSheet(
  BuildContext context, {
  required SeleccionDestinoViewModel vm,
}) async {
  await vm.cargarFavoritos();
  if (!context.mounted) return null;

  return showModalBottomSheet<UbicacionEntity>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (ctx) => AnimatedBuilder(
      animation: vm,
      builder: (context, _) => _FavoritosSheetContent(vm: vm),
    ),
  );
}

class _FavoritosSheetContent extends StatelessWidget {
  const _FavoritosSheetContent({required this.vm});

  final SeleccionDestinoViewModel vm;

  @override
  Widget build(BuildContext context) {
    final favoritos = vm.favoritos;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColores.grey300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              'Favoritos guardados',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            SizedBox(height: 12.h),
            if (vm.cargandoFavoritos)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (favoritos.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Text(
                  'No tienes favoritos guardados todavía.',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColores.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: favoritos.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1.h, color: AppColores.borderSubtle),
                  itemBuilder: (context, i) {
                    final favorito = favoritos[i];
                    return ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(favorito.nombre),
                      subtitle: Text(favorito.direccion),
                      onTap: () => Navigator.of(context).pop(favorito),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
