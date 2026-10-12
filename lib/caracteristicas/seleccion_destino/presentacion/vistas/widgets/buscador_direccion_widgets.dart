import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/boton.dart';

import '../../../dominio/entidades/ubicacion_entity.dart';

// Piezas del buscador de direcciones que comparten "¿A dónde vamos?"
// (`SeleccionDestinoScreen`) y el cambio de recogida/destino desde el
// detalle de la solicitud (`EditarUbicacionScreen`).

class CampoBuscarDireccion extends StatelessWidget {
  const CampoBuscarDireccion({
    super.key,
    this.etiqueta = 'Tu destino',
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onElegirEnMapa,
  });

  final String etiqueta;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onElegirEnMapa;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: context.palette.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: context.palette.grey100,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: context.palette.textSecondary,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: context.palette.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe una dirección (ej. Carrera 10 # 5-20)',
                      hintStyle: TextStyle(
                        fontSize: 13.sp,
                        color: context.palette.textSecondary,
                      ),
                      // El tema global define `filled`/bordes por-estado
                      // (enabled/focused) para todo TextField — solo pisar
                      // `border` no alcanza, esos ganan por sobre el
                      // genérico y el campo dibujaba su propio recuadro
                      // blanco anidado dentro de este contenedor gris.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    onChanged: onChanged,
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: context.palette.textSecondary,
                    ),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          CustomButton(
            text: 'Elegir en el mapa',
            width: double.infinity,
            height: 44.h,
            fontSize: 13.sp,
            color: context.palette.grey100,
            textColor: context.palette.textPrimary,
            borderColor: context.palette.borderSubtle,
            icon: Icon(Icons.map_rounded, size: 16, color: AppColores.primary),
            onPressed: onElegirEnMapa,
          ),
        ],
      ),
    );
  }
}

class ListaSugerencias extends StatelessWidget {
  const ListaSugerencias({
    super.key,
    required this.sugerencias,
    required this.onTap,
  });

  final List<UbicacionEntity> sugerencias;
  final ValueChanged<UbicacionEntity> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sugerencias.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1.h, indent: 64, color: context.palette.borderSubtle),
      itemBuilder: (context, i) {
        final sugerencia = sugerencias[i];
        final nombre = sugerencia.nombre.isNotEmpty
            ? sugerencia.nombre
            : sugerencia.direccion;
        final mostrarDireccion =
            sugerencia.direccion.isNotEmpty &&
            sugerencia.direccion != sugerencia.nombre;
        return InkWell(
          onTap: () => onTap(sugerencia),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
            child: Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration: BoxDecoration(
                    color: context.palette.grey100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: context.palette.textSecondary,
                    size: 18,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: context.palette.textPrimary,
                        ),
                      ),
                      if (mostrarDireccion) ...[
                        SizedBox(height: 2.h),
                        Text(
                          sugerencia.direccion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: context.palette.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Historial de destinos elegidos antes — mismo estilo de fila que
/// [ListaSugerencias], pero con ícono de reloj (son ubicaciones ya vistas,
/// no resultados de una búsqueda nueva).
class SeccionHistorial extends StatelessWidget {
  const SeccionHistorial({
    super.key,
    required this.historial,
    required this.onTap,
  });

  final List<UbicacionEntity> historial;
  final ValueChanged<UbicacionEntity> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in historial)
          InkWell(
            onTap: () => onTap(item),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      color: context.palette.grey100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      color: context.palette.textSecondary,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      item.direccion.isNotEmpty ? item.direccion : item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: context.palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Divider(height: 1.h, indent: 64, color: context.palette.borderSubtle),
      ],
    );
  }
}

class SeccionAcciones extends StatelessWidget {
  const SeccionAcciones({
    super.key,
    required this.onFavoritos,
    required this.onPegarUbicacion,
  });

  final VoidCallback onFavoritos;
  final VoidCallback onPegarUbicacion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CustomButton(
            text: 'Favoritos',
            width: double.infinity,
            height: 48.h,
            fontSize: 13.sp,
            color: context.palette.surface,
            textColor: context.palette.textPrimary,
            borderColor: context.palette.borderSubtle,
            icon: const Icon(
              Icons.star_rounded,
              size: 16,
              color: AppColores.primary,
            ),
            onPressed: onFavoritos,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: CustomButton(
            text: 'Pegar ubicación',
            width: double.infinity,
            height: 48.h,
            fontSize: 13.sp,
            color: context.palette.surface,
            textColor: context.palette.textPrimary,
            borderColor: context.palette.borderSubtle,
            icon: const Icon(
              Icons.content_paste_rounded,
              size: 16,
              color: AppColores.primary,
            ),
            onPressed: onPegarUbicacion,
          ),
        ),
      ],
    );
  }
}

class OverlayCargando extends StatelessWidget {
  const OverlayCargando({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: context.palette.overlayDark,
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 28.w),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColores.primary,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: context.palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
