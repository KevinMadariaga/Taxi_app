import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../utils/moneda_format.dart';
import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

/// Modal de selección de vehículo: dos cuadros (Carro/Moto) lado a lado con
/// imagen + precio sugerido, un campo editable para ajustar el valor del
/// servicio, y un botón "Confirmar vehículo" que aplica ambas elecciones.
/// Tocar un cuadro solo lo resalta y recarga el valor sugerido del campo
/// (selección local, sin efecto todavía) — hasta que se confirma no se toca
/// `vm.tipoVehiculo` ni `vm.valorServicio`, así el usuario puede comparar los
/// dos precios y editar el monto antes de decidir.
///
/// Devuelve `true` si el usuario confirmó (y por lo tanto `vm.tipoVehiculo`
/// y `vm.valorServicio` ya quedaron actualizados); `false`/`null` si cerró
/// sin confirmar (swipe, tocar afuera) — quien llama debe tratar eso como
/// cancelación, no seguir con el resto del flujo.
Future<bool?> mostrarTipoVehiculoSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TipoVehiculoSheetBody(vm: vm),
  );
}

class _TipoVehiculoSheetBody extends StatefulWidget {
  const _TipoVehiculoSheetBody({required this.vm});

  final ConfirmarSolicitudViewModel vm;

  @override
  State<_TipoVehiculoSheetBody> createState() => _TipoVehiculoSheetBodyState();
}

class _TipoVehiculoSheetBodyState extends State<_TipoVehiculoSheetBody> {
  late VehicleType _seleccionado;
  late final TextEditingController _valorController;
  String? _error;
  bool _isFormatting = false;

  @override
  void initState() {
    super.initState();
    _seleccionado = widget.vm.tipoVehiculo;
    _valorController = TextEditingController(
      text: formatCurrencyFromRaw(widget.vm.previsualizarValor(_seleccionado)),
    );
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  /// Cambia el vehículo resaltado y recarga el campo de valor con el precio
  /// sugerido de ese vehículo — descarta cualquier edición manual anterior,
  /// igual que `EditarOfertaBusquedaView` al cambiar de vehículo, porque un
  /// monto editado para "carro" no tiene sentido al pasar a "moto".
  void _seleccionarTipo(VehicleType tipo) {
    if (_seleccionado == tipo) return;
    setState(() {
      _seleccionado = tipo;
      _error = null;
      _valorController.text = formatCurrencyFromRaw(
        widget.vm.previsualizarValor(tipo),
      );
    });
  }

  void _onValorChanged(String value) {
    if (_isFormatting) return;
    final formatted = formatCurrencyFromRaw(value);
    if (formatted != value) {
      _isFormatting = true;
      _valorController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _isFormatting = false;
    }
    if (_error != null) setState(() => _error = null);
  }

  void _confirmar() {
    final error = widget.vm.validarValorServicio(
      _valorController.text,
      tipo: _seleccionado,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.vm.setTipoVehiculo(_seleccionado);
    widget.vm.setValorServicio(_valorController.text);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // `viewInsets.bottom` es el alto del teclado — sin sumarlo acá el sheet
    // se queda anclado al fondo de la pantalla y el teclado tapa el campo de
    // valor (que queda más abajo, después de los cuadros de vehículo).
    final teclado = MediaQuery.of(context).viewInsets.bottom;
    final palette = context.palette;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        12.w,
        0,
        12.w,
        teclado + MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20.r),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      color: palette.borderSubtle,
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
                      color: palette.textPrimary,
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
                      color: palette.textSecondary,
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
                          precio: widget.vm.previsualizarValor(tipo),
                          isSelected: _seleccionado == tipo,
                          onTap: () => _seleccionarTipo(tipo),
                        ),
                      ),
                      if (tipo != VehicleType.values.last)
                        SizedBox(width: 12.w),
                    ],
                  ],
                ),
                SizedBox(height: 18.h),
                Text(
                  'Valor del servicio',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: palette.textPrimary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Podés ajustar el monto antes de confirmar',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _valorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                    signed: false,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _onValorChanged,
                  onSubmitted: (_) => _confirmar(),
                  style: TextStyle(fontSize: 15.sp, color: palette.textPrimary),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    hintText: 'Ej: 11.000',
                    errorText: _error,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: BorderSide(
                        color: Colores.amarillo,
                        width: 2.w,
                      ),
                    ),
                  ),
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
                    onPressed: _confirmar,
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
  }
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
    final palette = context.palette;
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
              : palette.grey100,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? Colores.amarillo : palette.borderSubtle,
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
                color: palette.textPrimary,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              '\$${formatCurrencyFromRaw(precio)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.sp,
                color: palette.textPrimary,
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
