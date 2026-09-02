import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';

import '../../../dominio/casos_uso/buscar_destinos_usecase.dart';
import '../../../dominio/entidades/ubicacion_entity.dart';
import '../../viewmodels/seleccion_destino_viewmodel.dart';
import '../seleccionar_ubicacion_mapa_view.dart';
import 'etiqueta_favorito_dialog.dart';

sealed class _SheetAction {
  const _SheetAction();
}

class _Seleccionar extends _SheetAction {
  const _Seleccionar(this.favorito);
  final UbicacionEntity favorito;
}

class _Agregar extends _SheetAction {
  const _Agregar();
}

/// Lista de favoritos guardados, con acción de agregar y eliminar. Tocar uno
/// lo devuelve al caller (que llena el campo destino); "Agregar" y "Eliminar"
/// se resuelven acá adentro — el caller solo ve el resultado final de una
/// selección, o `null` si se cerró sin elegir nada.
Future<UbicacionEntity?> mostrarFavoritosBottomSheet(
  BuildContext context, {
  required SeleccionDestinoViewModel vm,
}) async {
  await vm.cargarFavoritos();
  if (!context.mounted) return null;

  final resultado = await showModalBottomSheet<_SheetAction>(
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

  if (resultado == null) return null;
  if (resultado is _Seleccionar) return resultado.favorito;

  // `_Agregar`: cierra el sheet, abre el picker de mapa + etiqueta, guarda,
  // y vuelve a abrir el sheet (recursivo) — el caller nunca ve este paso
  // intermedio, solo el resultado final.
  if (!context.mounted) return null;
  final picked = await Navigator.of(context).push<SeleccionUbicacionResult>(
    MaterialPageRoute(
      builder: (_) => SeleccionarUbicacionMapaView(
        ubicacionInicial: vm.origenPosition ?? BuscarDestinosUseCase.ocanaCenter,
        titulo: 'Elige la ubicación favorita',
      ),
    ),
  );
  if (!context.mounted) return null;
  if (picked == null) return mostrarFavoritosBottomSheet(context, vm: vm);

  final etiqueta = await mostrarEtiquetaFavoritoDialog(context);
  if (!context.mounted) return null;
  if (etiqueta == null) return mostrarFavoritosBottomSheet(context, vm: vm);

  final direccion = picked.direccion?.trim().isNotEmpty == true
      ? picked.direccion!.trim()
      : vm.coordsText(picked.position);
  final guardado = await vm.guardarFavorito(
    nombre: etiqueta,
    ubicacion: picked.position,
    direccion: direccion,
  );
  if (!context.mounted) return null;
  if (!guardado) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(vm.error ?? 'No se pudo guardar el favorito.')),
    );
  }
  return mostrarFavoritosBottomSheet(context, vm: vm);
}

class _FavoritosSheetContent extends StatelessWidget {
  const _FavoritosSheetContent({required this.vm});

  final SeleccionDestinoViewModel vm;

  Future<void> _eliminar(BuildContext context, UbicacionEntity favorito) async {
    final id = favorito.id;
    if (id == null) return;
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Eliminar favorito',
      mensaje: '¿Eliminar "${favorito.nombre}" de tus favoritos?',
      accion: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    final eliminado = await vm.eliminarFavorito(id);
    if (!eliminado && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.error ?? 'No se pudo eliminar el favorito.')),
      );
    }
  }

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Favoritos guardados',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColores.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(const _Agregar()),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            SizedBox(height: 8.h),
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
                    final sinUbicacion = favorito.position == null;
                    final eliminando =
                        vm.eliminandoFavoritoIds.contains(favorito.id);
                    return ListTile(
                      enabled: !sinUbicacion,
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(favorito.nombre),
                      subtitle: Text(
                        sinUbicacion
                            ? 'Sin ubicación guardada'
                            : favorito.direccion,
                      ),
                      trailing: IconButton(
                        icon: eliminando
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline,
                                color: AppColores.error,
                              ),
                        tooltip: 'Eliminar favorito',
                        onPressed: eliminando
                            ? null
                            : () => _eliminar(context, favorito),
                      ),
                      onTap: sinUbicacion
                          ? null
                          : () => Navigator.of(context).pop(
                                _Seleccionar(favorito),
                              ),
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
