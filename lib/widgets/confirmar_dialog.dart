import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Diálogo de confirmación estándar de la app. Un solo estilo para toda
/// acción destructiva o que necesite doble check antes de ejecutarse
/// (extraído del que vivía duplicado en `admin_home_screen.dart`).
Future<bool> mostrarConfirmacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Aceptar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: peligro
              ? FilledButton.styleFrom(backgroundColor: AppColores.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return r == true;
}
