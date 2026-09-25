import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;

import 'package:taxi_app/caracteristicas/confirmar_solicitud/dominio/casos_uso/calcular_tarifa_base_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/modelos/vehicle_type.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';
import 'package:taxi_app/core/app_tamano.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Pantalla propia (no bottom sheet) para editar la oferta de una búsqueda en
/// curso: valor ofrecido y tipo de vehículo, en una sola clase — reemplaza al
/// modal `_abrirModalEditarValor` que antes vivía en `BuscandoTaxiView` y solo
/// dejaba cambiar el valor.
///
/// Recibe el mismo `BuscandoTaxiViewModel` que ya usa `BuscandoTaxiView` (no
/// una copia): al guardar, escribe directo en Firestore vía el VM, que ya
/// dispara `notifyListeners()` — la pantalla de atrás se entera en vivo (su
/// propio listener de Firestore también lo confirma apenas llega el eco),
/// sin depender de que esta pantalla haga nada especial al volver.
class EditarOfertaBusquedaView extends StatefulWidget {
  const EditarOfertaBusquedaView({super.key, required this.vm});

  final BuscandoTaxiViewModel vm;

  @override
  State<EditarOfertaBusquedaView> createState() =>
      _EditarOfertaBusquedaViewState();
}

class _EditarOfertaBusquedaViewState extends State<EditarOfertaBusquedaView> {
  static const _calcularTarifaBase = CalcularTarifaBaseUseCase();

  late final TextEditingController _controller;
  late VehicleType _tipoSeleccionado;
  late final double? _distanciaKm;
  bool _isFormatting = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Ruta ya trazada por `BuscandoTaxiViewModel` (misma ruta que ve el
    // mapa de fondo) — se usa para que el valor sugerido al cambiar de
    // vehículo escale con la distancia real, no un monto fijo.
    _distanciaKm = widget.vm.routePoints.length >= 2
        ? MapHelper.routeDistanceMeters(widget.vm.routePoints) / 1000.0
        : null;
    final initialDigits = widget.vm.valorServicioActual > 0
        ? widget.vm.valorServicioActual.round().toString()
        : '10000';
    final initialFormatted = _formatInput(initialDigits);
    _controller = TextEditingController(text: initialFormatted)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialFormatted.length,
      );
    _tipoSeleccionado = widget.vm.isMotoSolicitud
        ? VehicleType.moto
        : VehicleType.carro;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatCurrency(num value) {
    final asInt = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < asInt.length; i++) {
      final reverseIndex = asInt.length - i;
      buf.write(asInt[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buf.write('.');
      }
    }
    return buf.toString();
  }

  String _formatInput(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final parsed = int.tryParse(digits) ?? 0;
    return _formatCurrency(parsed);
  }

  List<int> _buildSuggestions() {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final current = int.tryParse(digits) ?? 5000;
    final base = current < 5000 ? 5000 : current;
    return [base + 500, base + 1000, base + 1500, base + 2000];
  }

  void _aplicarValor(String formatted) {
    setState(() {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
  }

  /// Cambia el tipo de vehículo seleccionado y recalcula el valor sugerido
  /// (tarifa base + distancia real) — así el cuadro de texto y las
  /// sugerencias de abajo (derivadas del texto) reflejan el vehículo nuevo
  /// en vez de quedarse con el monto del vehículo anterior.
  void _seleccionarTipoVehiculo(VehicleType tipo) {
    if (_tipoSeleccionado == tipo) return;
    final sugerido = _calcularTarifaBase(tipo, distanciaKm: _distanciaKm);
    final formatted = _formatInput(sugerido);
    setState(() {
      _error = null;
      _tipoSeleccionado = tipo;
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Misma regla de monto que el diálogo "¿Sigues buscando?" y que el sheet
    // de antes de crear la solicitud. Antes acá solo se exigía `> 0`, así
    // que por este camino un $1 entraba a Firestore igual.
    final error = widget.vm.validarNuevoValor(digits, tipo: _tipoSeleccionado);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final nuevoValor = double.parse(digits);

    setState(() {
      _error = null;
      _guardando = true;
    });

    final cambioVehiculo =
        _tipoSeleccionado.firestoreKey != widget.vm.tipoVehiculo;
    final cambioValor = nuevoValor != widget.vm.valorServicioActual;

    bool ok = true;
    if (cambioVehiculo) {
      final vehiculoOk = await widget.vm.actualizarTipoVehiculo(
        _tipoSeleccionado.firestoreKey,
      );
      ok = ok && vehiculoOk;
    }
    if (!mounted) return;
    if (cambioValor) {
      final valorOk = await widget.vm.actualizarValorServicio(nuevoValor);
      ok = ok && valorOk;
    }
    if (!mounted) return;

    setState(() => _guardando = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar. Intenta de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: appBarNeutra(
        context,
        titulo: 'Editar oferta',
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿Cuánto ofreces por el servicio?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: context.palette.textPrimary,
                ),
              ),
              SizedBox(height: 10.h),
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                  signed: false,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  if (_isFormatting) return;
                  final formatted = _formatInput(value);
                  if (formatted == value) return;
                  _isFormatting = true;
                  _aplicarValor(formatted);
                  _isFormatting = false;
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _guardar(),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: context.palette.textPrimary,
                ),
                // Bordes, relleno y radios del tema (`inputDecorationTheme`),
                // que ya se adaptan a claro/oscuro; solo se engrosa el foco.
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: context.palette.textPrimary,
                  ),
                  hintText: 'Ej: 11.000',
                  hintStyle: TextStyle(color: context.palette.textSecondary),
                  errorText: _error,
                  errorStyle: TextStyle(color: context.palette.errorText),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTamano.radiusMD),
                    borderSide: BorderSide(
                      color: AppColores.primary,
                      width: 2.w,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _buildSuggestions().map((value) {
                  return ActionChip(
                    backgroundColor: context.palette.surface,
                    side: BorderSide(color: context.palette.borderSubtle),
                    shape: const StadiumBorder(),
                    label: Text(
                      '\$${_formatCurrency(value)}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    onPressed: () => _aplicarValor(_formatCurrency(value)),
                  );
                }).toList(),
              ),
              SizedBox(height: 28.h),
              Text(
                'Tipo de vehículo',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: context.palette.textPrimary,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Elige el vehículo con el que quieres viajar',
                style: TextStyle(
                  fontSize: 12.5.sp,
                  color: context.palette.textSecondary,
                ),
              ),
              SizedBox(height: 14.h),
              Row(
                children: VehicleType.values.map((tipo) {
                  final isSelected = _tipoSeleccionado == tipo;
                  final vehicleAsset = tipo == VehicleType.moto
                      ? 'assets/img/icono_moto.png'
                      : 'assets/img/icono_carro.png';
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6.w),
                      child: GestureDetector(
                        onTap: () => _seleccionarTipoVehiculo(tipo),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            vertical: 18.h,
                            horizontal: 10.w,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColores.primary.withValues(alpha: 0.14)
                                : context.palette.surface,
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isSelected
                                  ? AppColores.primary
                                  : context.palette.borderSubtle,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                vehicleAsset,
                                height: 40.h,
                                fit: BoxFit.contain,
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                tipo.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.sp,
                                  color: context.palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 32.h),
              CustomButton(
                text: 'Guardar cambios',
                width: double.infinity,
                height: 52.h,
                isLoading: _guardando,
                onPressed: _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
