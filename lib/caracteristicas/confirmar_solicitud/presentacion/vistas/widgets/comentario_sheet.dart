import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

/// Tope del comentario al conductor. Suficiente para una indicación de
/// recogida ("portón blanco, timbre roto") sin desbordar la tarjeta de
/// preview ni permitir texto arbitrariamente largo en el documento.
const int _maxCaracteresComentario = 140;

Future<void> mostrarComentarioSheet(
  BuildContext context,
  ConfirmarSolicitudViewModel vm,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _ComentarioSheet(vm: vm),
  );
}

/// El contenido es un `StatefulWidget` —y no un `StatefulBuilder` con el
/// controller creado en la función— para que el `TextEditingController` viva
/// exactamente lo que vive la ruta del sheet.
///
/// Antes el controller se creaba antes de `showModalBottomSheet` y se disponía
/// en la línea siguiente al `await`. Ese `await` completa cuando se hace pop,
/// pero el sheet sigue animando su salida y se reconstruye durante la
/// transición: el `TextField` volvía a usar un controller ya disposed y
/// lanzaba "A TextEditingController was used after being disposed", seguido de
/// un overflow de ~99.600 px y un `_dependents.isEmpty`. Reproducido igual en
/// Android e iOS al cerrar el sheet con el teclado abierto.
class _ComentarioSheet extends StatefulWidget {
  const _ComentarioSheet({required this.vm});

  final ConfirmarSolicitudViewModel vm;

  @override
  State<_ComentarioSheet> createState() => _ComentarioSheetState();
}

class _ComentarioSheetState extends State<_ComentarioSheet> {
  static const _sugerencias = <(IconData, String)>[
    (Icons.pets_rounded, 'Llevo mascota'),
    (Icons.luggage_rounded, 'Llevo maletas'),
  ];

  late final TextEditingController _controller;
  late String _draft;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.vm.comentario);
    _draft = widget.vm.comentario;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _aplicarSugerencia(String sugerencia) {
    setState(() {
      _draft = sugerencia;
      _controller.value = TextEditingValue(
        text: sugerencia,
        selection: TextSelection.collapsed(offset: sugerencia.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final palette = context.palette;
    final tieneGuardada = widget.vm.comentario.isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        (keyboardInset > 0 ? keyboardInset : media.viewPadding.bottom) + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nota para el conductor',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'La verá al recibir tu solicitud. Útil para indicar dónde '
            'esperas o qué llevas.',
            style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icono, texto) in _sugerencias)
                ActionChip(
                  avatar: Icon(icono, size: 18, color: AppColores.primary),
                  label: Text(texto),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  backgroundColor: _draft == texto
                      ? AppColores.primary.withValues(alpha: 0.18)
                      : palette.grey100,
                  side: BorderSide(
                    color: _draft == texto
                        ? AppColores.primary
                        : palette.borderSubtle,
                  ),
                  shape: const StadiumBorder(),
                  onPressed: () => _aplicarSugerencia(texto),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            // Sin tope, el único techo era el límite de 1 MiB por
            // documento de Firestore: se podía guardar un texto
            // arbitrariamente largo que además se renderiza sin truncar en
            // la preview del conductor.
            maxLength: _maxCaracteresComentario,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxCaracteresComentario),
            ],
            onChanged: (value) => setState(() => _draft = value.trim()),
            cursorColor: AppColores.primary,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ej. Estoy en el portón blanco',
              hintStyle: TextStyle(color: palette.textSecondary),
              filled: true,
              fillColor: palette.background,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.grey300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColores.primary,
                  width: 1.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                widget.vm.setComentario(_draft);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.buttonPrimary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Guardar nota',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (tieneGuardada)
            TextButton(
              onPressed: () {
                widget.vm.setComentario('');
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(foregroundColor: AppColores.error),
              child: const Text(
                'Quitar nota',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
