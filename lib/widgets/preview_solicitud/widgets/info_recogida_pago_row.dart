import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Fila "Recoger en" (izquierda) | "Pagará con" (derecha) — separadas por
/// un divisor vertical.
class InfoRecogidaPagoRow extends StatelessWidget {
  const InfoRecogidaPagoRow({
    super.key,
    required this.direccionRecogida,
    required this.metodoPago,
  });

  final String direccionRecogida;
  final String? metodoPago;

  static String _formatMetodo(String? metodo) {
    if (metodo == null || metodo.isEmpty) return '—';
    final lower = metodo.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  static IconData _iconoMetodo(String? metodo) {
    final lower = (metodo ?? '').toLowerCase();
    if (lower.contains('efectivo')) return Icons.attach_money;
    if (lower.contains('transfer') || lower.contains('nequi')) {
      return Icons.credit_card;
    }
    return Icons.payment;
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _InfoColumn(
              label: 'Recoger en',
              child: Text(
                direccionRecogida,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColores.textPrimary,
                ),
              ),
            ),
          ),
          const VerticalDivider(
            color: AppColores.borderSubtle,
            width: 24,
            thickness: 1,
          ),
          Expanded(
            child: _InfoColumn(
              label: 'Pagará con',
              alignEnd: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    _iconoMetodo(metodoPago),
                    color: AppColores.primary,
                    size: 15,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _formatMetodo(metodoPago),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({
    required this.label,
    required this.child,
    this.alignEnd = false,
  });

  final String label;
  final Widget child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 12,
            color: AppColores.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}
