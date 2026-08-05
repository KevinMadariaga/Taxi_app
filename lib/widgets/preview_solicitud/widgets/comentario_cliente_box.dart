import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Comentario del cliente para el conductor. `null`/vacío/valores genéricos
/// ("ninguno", "n/a", "-"...) se normalizan a `null` antes de llegar acá —
/// ver [normalizar].
class ComentarioClienteBox extends StatelessWidget {
  const ComentarioClienteBox({super.key, required this.comentario});

  final String comentario;

  /// `null` si [raw] está vacío o es un valor "genérico" sin información
  /// real (p.ej. lo que queda cuando el campo se guardó como texto libre
  /// pero el cliente no escribió nada).
  static String? normalizar(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'null' ||
        lower == 'ninguno' ||
        lower == 'sin comentario' ||
        lower == 'n/a' ||
        lower == 'na' ||
        text == '-') {
      return null;
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColores.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 15,
            color: AppColores.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comentario del cliente',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comentario,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColores.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
