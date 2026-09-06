import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/boton.dart';

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
  // `null` = nada seleccionado todavía. Antes arrancaba en 'Otro' por
  // defecto, lo que mostraba el campo de texto con el teclado abierto ni
  // bien aparecía el diálogo, sin que el usuario tocara nada.
  String? _seleccionado;

  @override
  void initState() {
    super.initState();
    final inicial = widget.etiquetaInicial?.trim() ?? '';
    _seleccionado = _etiquetasSugeridas.contains(inicial) ? inicial : null;
    _controller = TextEditingController(
      text: _seleccionado == null && inicial.isNotEmpty ? inicial : '',
    );
    if (_controller.text.isNotEmpty) _seleccionado = 'Otro';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _nombreFinal {
    if (_seleccionado == null) return null;
    if (_seleccionado != 'Otro') return _seleccionado;
    final texto = _controller.text.trim();
    return texto.isEmpty ? null : texto;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Guardar como favorito'),
      // Sin esto, el `TextField` que aparece al elegir "Otro" (con el
      // teclado ya abierto) puede desbordar la modal en pantallas chicas.
      scrollable: true,
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: CustomButton(
                text: 'Guardar',
                color: AppColores.buttonPrimary,
                textColor: AppColores.textWhite,
                height: 44,
                fontSize: 14,
                onPressed: _nombreFinal == null
                    ? null
                    : () => Navigator.of(context).pop(_nombreFinal),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
