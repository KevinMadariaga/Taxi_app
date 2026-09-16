import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

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

  static bool _esNequi(String? metodo) =>
      (metodo ?? '').toLowerCase().contains('nequi');

  static IconData _iconoMetodo(String? metodo) {
    final lower = (metodo ?? '').toLowerCase();
    if (lower.contains('efectivo')) return Icons.attach_money;
    if (lower.contains('transfer')) return Icons.credit_card;
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
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ),
          VerticalDivider(
            color: context.palette.borderSubtle,
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
                  _esNequi(metodoPago)
                      ? Container(
                          width: 16,
                          height: 16,
                          padding: const EdgeInsets.all(1.5),
                          decoration: const BoxDecoration(
                            // El logo de Nequi lleva navy sólido en el
                            // centro: sobre un fondo oscuro se pierde, así
                            // que el chip lleva blanco fijo — mismo criterio
                            // que `metodo_pago_card.dart`.
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset('assets/img/nequi.png'),
                        )
                      : Icon(
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
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.textPrimary,
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
          style: TextStyle(
            fontSize: 12,
            color: context.palette.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}
