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
    return AlertDialog(
      title: const Text('Activar membresía'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Por cuántos días se activa el servicio?'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            // Sin `autofocus`: el teclado no debe abrirse solo al aparecer
            // el diálogo — la mayoría de las veces alcanza con tocar uno de
            // los chips de días de abajo, sin necesidad de escribir nada.
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Días',
              suffixText: 'días',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _diasSugeridos.map((dias) {
              return ChoiceChip(
                label: Text('$dias días'),
                selected: _controller.text.trim() == '$dias',
                onSelected: (_) => _elegirDias(dias),
                selectedColor: AppColores.primary.withValues(alpha: 0.2),
                side: BorderSide(
                  color: _controller.text.trim() == '$dias'
                      ? AppColores.primary
                      : context.palette.borderSubtle,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: CustomButton(
                text: 'Cancelar',
                color: context.palette.surface,
                textColor: AppColores.primary,
                borderColor: AppColores.primary,
                height: 44,
                fontSize: 14,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomButton(
                text: 'Aprobar',
                color: AppColores.buttonPrimary,
                textColor: AppColores.textWhite,
                height: 44,
                fontSize: 14,
                onPressed: () {
                  final dias = int.tryParse(_controller.text.trim());
                  if (dias == null || dias <= 0) return;
                  Navigator.pop(context, dias);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
