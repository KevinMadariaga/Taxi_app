import 'package:flutter/material.dart';

import 'package:taxi_app/core/theme/app_palette.dart';

/// Lista corta de motivos para que el conductor cancele el viaje. Devuelve el
/// motivo elegido o `null` si cerró la hoja.
class MotivoCancelacionSheet extends StatelessWidget {
  const MotivoCancelacionSheet._();

  static const motivos = [
    'El cliente no aparece',
    'El cliente pidió cancelar',
    'Dirección incorrecta o inaccesible',
    'Problema con el vehículo',
    'Otro motivo',
  ];

  static Future<String?> mostrar(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const MotivoCancelacionSheet._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Por qué cancelas el viaje?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            for (final motivo in motivos)
              ListTile(
                minTileHeight: 52,
                title: Text(
                  motivo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textSecondary,
                ),
                onTap: () => Navigator.pop(context, motivo),
              ),
          ],
        ),
      ),
    );
  }
}
