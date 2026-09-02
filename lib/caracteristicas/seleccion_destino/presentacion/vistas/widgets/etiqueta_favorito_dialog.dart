import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';

const List<String> _etiquetasSugeridas = ['Casa', 'Trabajo', 'Otro'];

/// Pide el nombre/etiqueta con el que se va a guardar un favorito nuevo:
/// tres chips (Casa/Trabajo/Otro) + campo libre habilitado solo en "Otro".
/// Devuelve el nombre final, o `null` si el usuario canceló.
Future<String?> mostrarEtiquetaFavoritoDialog(
  BuildContext context, {
  String? etiquetaInicial,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EtiquetaFavoritoDialog(etiquetaInicial: etiquetaInicial),
  );
}

class _EtiquetaFavoritoDialog extends StatefulWidget {
  const _EtiquetaFavoritoDialog({this.etiquetaInicial});

  final String? etiquetaInicial;

  @override
  State<_EtiquetaFavoritoDialog> createState() =>
      _EtiquetaFavoritoDialogState();
}

class _EtiquetaFavoritoDialogState extends State<_EtiquetaFavoritoDialog> {
  late final TextEditingController _controller;
  late String _seleccionado;

  @override
  void initState() {
    super.initState();
    final inicial = widget.etiquetaInicial?.trim() ?? '';
    _seleccionado = _etiquetasSugeridas.contains(inicial) ? inicial : 'Otro';
    _controller = TextEditingController(
      text: _seleccionado == 'Otro' ? inicial : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _nombreFinal {
    if (_seleccionado != 'Otro') return _seleccionado;
    final texto = _controller.text.trim();
    return texto.isEmpty ? null : texto;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Guardar como favorito'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8.w,
            children: _etiquetasSugeridas.map((etiqueta) {
              return ChoiceChip(
                label: Text(etiqueta),
                selected: _seleccionado == etiqueta,
                onSelected: (_) => setState(() => _seleccionado = etiqueta),
                selectedColor: AppColores.primary.withValues(alpha: 0.18),
              );
            }).toList(),
          ),
          if (_seleccionado == 'Otro') ...[
            SizedBox(height: 12.h),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre del lugar',
                hintText: 'Ej: Casa de mamá',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _nombreFinal == null
              ? null
              : () => Navigator.of(context).pop(_nombreFinal),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
