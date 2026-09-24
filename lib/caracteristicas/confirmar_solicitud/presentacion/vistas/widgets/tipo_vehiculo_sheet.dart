import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import 'package:taxi_app/core/utils/moneda_format.dart';
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
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
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
    final media = MediaQuery.of(context);
    final teclado = media.viewInsets.bottom;
    final palette = context.palette;
    final conError = _error != null;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: teclado),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            (teclado > 0 ? 0 : media.viewPadding.bottom) + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Elige tu vehículo',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'El precio sugerido cambia según el vehículo.',
                style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
              ),
              const SizedBox(height: 18),
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
                      const SizedBox(width: 12),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Valor del servicio',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Puedes ajustar el monto antes de confirmar.',
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
              const SizedBox(height: 10),
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
                cursorColor: AppColores.primary,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: Text(
                      '\$',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(),
                  hintText: '11.000',
                  hintStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.textSecondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: palette.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: conError ? AppColores.error : palette.grey300,
                      width: conError ? 1.8 : 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: conError ? AppColores.error : AppColores.primary,
                      width: 1.8,
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: !conError
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: AppColores.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColores.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _confirmar,
                  child: const Text(
                    'Confirmar vehículo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
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

    return Material(
      color: isSelected
          ? Color.alphaBlend(
              AppColores.primary.withValues(alpha: 0.12),
              palette.surface,
            )
          : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected ? AppColores.primary : palette.borderSubtle,
          width: isSelected ? 2 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 14),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(vehicleAsset, height: 58, fit: BoxFit.contain),
                    const SizedBox(height: 10),
                    Text(
                      tipo.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$${formatCurrencyFromRaw(precio)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isSelected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isSelected)
              const Positioned(
                top: 10,
                right: 10,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: AppColores.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
