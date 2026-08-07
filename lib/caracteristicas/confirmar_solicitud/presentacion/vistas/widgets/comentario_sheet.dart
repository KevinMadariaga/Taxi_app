import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    backgroundColor: Colors.transparent,
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
  static const _sugerencias = <String>['Llevo mascota', 'Llevo maletas'];

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
    final bottomGap = keyboardInset > 0
        ? keyboardInset + 10
        : media.viewPadding.bottom + 10;
    final comentarioGuardado = widget.vm.comentario;

    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, bottomGap),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comentario para el conductor',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
              ),
              SizedBox(height: 4.h),
              Text(
                comentarioGuardado.isEmpty
                    ? 'Sin comentario guardado'
                    : 'Guardado: $comentarioGuardado',
                style: const TextStyle(color: Colors.black54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8,
                children: _sugerencias
                    .map(
                      (s) => ActionChip(
                        label: Text(s),
                        onPressed: () => _aplicarSugerencia(s),
                      ),
                    )
                    .toList(),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: _controller,
                maxLines: 3,
                // Sin tope, el único techo era el límite de 1 MiB por
                // documento de Firestore: se podía guardar un texto
                // arbitrariamente largo que además se renderiza sin
                // truncar en la preview del conductor.
                maxLength: _maxCaracteresComentario,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxCaracteresComentario),
                ],
                onChanged: (value) => _draft = value.trim(),
                decoration: const InputDecoration(
                  hintText: 'Escribe un comentario...',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.vm.setComentario(_draft);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Guardar comentario'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
