import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/boton.dart';

const List<int> _diasSugeridos = [7, 15, 30, 60, 90];

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
    _controller = TextEditingController(text: '30');
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
                  suffixText: 'días',
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
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _diasSugeridos.map((dias) {
                  final seleccionado = _controller.text.trim() == '$dias';
                  return ChoiceChip(
                    avatar: Icon(
                      Icons.event_available_rounded,
                      size: 18,
                      color: seleccionado
                          ? AppColores.primary
                          : palette.textSecondary,
                    ),
                    showCheckmark: false,
                    label: Text('$dias días'),
                    selected: seleccionado,
                    onSelected: (_) => _elegirDias(dias),
                    selectedColor: AppColores.primary.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: seleccionado
                          ? AppColores.primary
                          : palette.borderSubtle,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Cancelar',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColores.primary,
                        size: 20,
                      ),
                      color: palette.surface,
                      textColor: AppColores.primary,
                      borderColor: AppColores.primary,
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
                        color: AppColores.textWhite,
                        size: 20,
                      ),
                      color: AppColores.buttonPrimary,
                      textColor: AppColores.textWhite,
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
