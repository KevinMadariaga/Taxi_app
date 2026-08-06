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
) async {
  final controller = TextEditingController(text: vm.comentario);
  String draft = vm.comentario;
  const sugerencias = <String>['Llevo mascota', 'Llevo maletas'];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final keyboardInset = media.viewInsets.bottom;
      final bottomGap = keyboardInset > 0
          ? keyboardInset + 10
          : media.viewPadding.bottom + 10;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      vm.comentario.isEmpty
                          ? 'Sin comentario guardado'
                          : 'Guardado: ${vm.comentario}',
                      style: const TextStyle(color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 10.h),
                    Wrap(
                      spacing: 8,
                      children: sugerencias
                          .map(
                            (s) => ActionChip(
                              label: Text(s),
                              onPressed: () {
                                setSheetState(() {
                                  draft = s;
                                  controller.text = s;
                                  controller.selection =
                                      TextSelection.collapsed(
                                        offset: controller.text.length,
                                      );
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      // Sin tope, el único techo era el límite de 1 MiB por
                      // documento de Firestore: se podía guardar un texto
                      // arbitrariamente largo que además se renderiza sin
                      // truncar en la preview del conductor.
                      maxLength: _maxCaracteresComentario,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          _maxCaracteresComentario,
                        ),
                      ],
                      onChanged: (value) {
                        setSheetState(() {
                          draft = value.trim();
                        });
                      },
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
                          vm.setComentario(draft);
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Guardar comentario'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  controller.dispose();
}
