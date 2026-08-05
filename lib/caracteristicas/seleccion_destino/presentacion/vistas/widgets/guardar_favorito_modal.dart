import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';

import '../../viewmodels/seleccion_destino_viewmodel.dart';
import '../seleccionar_ubicacion_mapa_view.dart';

/// Bottom sheet "Guardar ubicación en favoritos": nombre + dirección
/// (ajustable en el mapa) + botón Guardar. La misma hoja sirve tanto para el
/// ícono de estrella sobre "Mi ubicación" como para el botón "Agregar
/// favorito" — solo cambia la posición/dirección inicial con la que se abre.
///
/// Devuelve `true` si se guardó, `null`/`false` si se canceló.
Future<bool?> mostrarGuardarFavoritoModal(
  BuildContext context, {
  required SeleccionDestinoViewModel vm,
  required LatLng posicionInicial,
  required String direccionInicial,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (ctx) => _GuardarFavoritoSheet(
      vm: vm,
      posicionInicial: posicionInicial,
      direccionInicial: direccionInicial,
    ),
  );
}

class _GuardarFavoritoSheet extends StatefulWidget {
  const _GuardarFavoritoSheet({
    required this.vm,
    required this.posicionInicial,
    required this.direccionInicial,
  });

  final SeleccionDestinoViewModel vm;
  final LatLng posicionInicial;
  final String direccionInicial;

  @override
  State<_GuardarFavoritoSheet> createState() => _GuardarFavoritoSheetState();
}

class _GuardarFavoritoSheetState extends State<_GuardarFavoritoSheet> {
  final _nombreController = TextEditingController();
  late LatLng _posicion = widget.posicionInicial;
  late String _direccion = widget.direccionInicial;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _ajustarEnMapa() async {
    final resultado = await Navigator.of(context)
        .push<SeleccionUbicacionResult>(
          MaterialPageRoute(
            builder: (_) => SeleccionarUbicacionMapaView(
              ubicacionInicial: _posicion,
              titulo: 'Ajusta la ubicación',
              direccionInicial: _direccion,
            ),
          ),
        );
    if (resultado == null || !mounted) return;
    setState(() {
      _posicion = resultado.position;
      _direccion = resultado.direccion?.trim().isNotEmpty == true
          ? resultado.direccion!.trim()
          : _direccion;
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    final ok = await widget.vm.guardarFavorito(
      nombre: nombre,
      ubicacion: _posicion,
      direccion: _direccion,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.vm.error ?? 'No se pudo guardar.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
                'Guardar ubicación en favoritos',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                '¿Cómo quieres que se llame?',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColores.textSecondary,
                ),
              ),
              SizedBox(height: 6.h),
              TextField(
                controller: _nombreController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ej. Casa de mis papás',
                  filled: true,
                  fillColor: AppColores.grey100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                'Esta es la dirección',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColores.textSecondary,
                ),
              ),
              SizedBox(height: 6.h),
              InkWell(
                onTap: _ajustarEnMapa,
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  decoration: BoxDecoration(
                    color: AppColores.grey100,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColores.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AppColores.primary,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          _direccion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.edit_location_alt_outlined,
                        size: 18,
                        color: AppColores.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              CustomButton(
                text: 'Guardar',
                width: double.infinity,
                height: 52.h,
                isLoading: _guardando,
                onPressed: _nombreController.text.trim().isEmpty
                    ? null
                    : _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
