import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/boton.dart';

/// "1 día" / "N días" (sin "1 días").
String textoDias(Object? dias) => '$dias' == '1' ? '1 día' : '$dias días';

// 1 día primero (y preseleccionado): para probar o activar por un día.
const List<int> _diasSugeridos = [1, 7, 15, 30, 60, 90];

/// Pide "¿por cuántos días se activa el servicio?" y devuelve la cantidad,
/// o `null` si se cancela. Compartido entre el panel admin (pestaña
/// Conductores) y la pestaña "Activaciones" de Gestión — antes vivía
/// duplicado/privado en `admin_home_screen.dart`.
Future<int?> mostrarDialogoDiasMembresia(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _DialogoDiasMembresia(),
  );
}

class _DialogoDiasMembresia extends StatefulWidget {
  const _DialogoDiasMembresia();

  @override
  State<_DialogoDiasMembresia> createState() => _DialogoDiasMembresiaState();
}

class _DialogoDiasMembresiaState extends State<_DialogoDiasMembresia> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${_diasSugeridos.first}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _elegirDias(int dias) {
    setState(() {
      _controller.value = TextEditingValue(
        text: '$dias',
        selection: TextSelection.collapsed(offset: '$dias'.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final diasValidos = (int.tryParse(_controller.text.trim()) ?? 0) > 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        // Tope de ancho: en tablet el diálogo no se estira de lado a lado.
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColores.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  size: 40,
                  color: AppColores.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Activar membresía',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '¿Por cuántos días se activa el servicio?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: palette.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                // Sin `autofocus`: el teclado no debe abrirse solo al aparecer
                // el diálogo — la mayoría de las veces alcanza con tocar uno de
                // los chips de días de abajo, sin necesidad de escribir nada.
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.calendar_month_rounded,
                    color: AppColores.primary,
                  ),
                  suffixText: _controller.text.trim() == '1' ? 'día' : 'días',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColores.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < _diasSugeridos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _CuadroDias(
                        dias: _diasSugeridos[i],
                        seleccionado:
                            _controller.text.trim() == '${_diasSugeridos[i]}',
                        onTap: () => _elegirDias(_diasSugeridos[i]),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Cancelar',
                      icon: Icon(
                        Icons.close_rounded,
                        color: context.palette.textPrimary,
                        size: 20,
                      ),
                      color: palette.surface,
                      textColor: context.palette.textPrimary,
                      borderColor: context.palette.grey300,
                      height: 48,
                      fontSize: 15,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      text: 'Aprobar',
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                      color: AppColores.buttonPrimary,
                      textColor: Colors.black,
                      height: 48,
                      fontSize: 15,
                      onPressed: diasValidos
                          ? () => Navigator.pop(
                              context,
                              int.parse(_controller.text.trim()),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opción rápida de días: cuadros iguales en fila. Seleccionado = relleno
/// ámbar con texto negro (contraste alto en claro y en oscuro); el resto,
/// fondo y texto del tema.
class _CuadroDias extends StatelessWidget {
  const _CuadroDias({
    required this.dias,
    required this.seleccionado,
    required this.onTap,
  });

  final int dias;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colorTexto = seleccionado ? Colors.black : palette.textPrimary;
    return Semantics(
      button: true,
      selected: seleccionado,
      label: textoDias(dias),
      child: Material(
        color: seleccionado ? AppColores.primary : palette.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: seleccionado ? AppColores.primary : palette.grey300,
            width: seleccionado ? 2 : 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$dias',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: colorTexto,
                    ),
                  ),
                ),
                Text(
                  dias == 1 ? 'día' : 'días',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: seleccionado
                        ? Colors.black87
                        : palette.textSecondary,
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
