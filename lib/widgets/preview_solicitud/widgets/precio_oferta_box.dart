import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Bloque de precio: oferta original del cliente y, si el conductor ya
/// contraofertó, el valor contraofertado — ambos en la misma línea (servicio
/// a la izquierda, contraoferta a la derecha) en vez de apilados, para que
/// se lean como una comparación directa de un vistazo.
class PrecioOfertaBox extends StatelessWidget {
  const PrecioOfertaBox({
    super.key,
    required this.valorCliente,
    this.valorContraoferta,
  });

  final double valorCliente;
  final double? valorContraoferta;

  static String _formatCurrency(num value) {
    final asInt = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < asInt.length; i++) {
      final reverseIndex = asInt.length - i;
      buf.write(asInt[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buf.write('.');
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final valorContra = valorContraoferta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColores.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: valorContra == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Text(
                    'Valor del servicio',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '\$${_formatCurrency(valorCliente)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: AppColores.success,
                  ),
                ),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PrecioColumna(
                      label: 'Valor del servicio',
                      valor: valorCliente,
                      alignment: CrossAxisAlignment.start,
                      textAlign: TextAlign.left,
                      valorColor: AppColores.success,
                      valorFontSize: 17,
                      strikethrough: true,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColores.borderSubtle,
                    ),
                  ),
                  Expanded(
                    child: _PrecioColumna(
                      label: 'Tu contraoferta',
                      valor: valorContra,
                      alignment: CrossAxisAlignment.end,
                      textAlign: TextAlign.right,
                      valorColor: AppColores.primaryDark,
                      valorFontSize: 22,
                      icon: Icons.local_offer_outlined,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PrecioColumna extends StatelessWidget {
  const _PrecioColumna({
    required this.label,
    required this.valor,
    required this.alignment,
    required this.textAlign,
    required this.valorColor,
    required this.valorFontSize,
    this.icon,
    this.strikethrough = false,
  });

  final String label;
  final double valor;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;
  final Color valorColor;
  final double valorFontSize;
  final IconData? icon;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon == null)
          Text(
            label,
            textAlign: textAlign,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColores.textSecondary,
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColores.primaryDark),
              const SizedBox(width: 4),
              Text(
                label,
                textAlign: textAlign,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColores.primaryDark,
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(
          '\$${PrecioOfertaBox._formatCurrency(valor)}',
          textAlign: textAlign,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: valorFontSize,
            color: valorColor,
            decoration: strikethrough ? TextDecoration.lineThrough : null,
            decorationColor: AppColores.textSecondary,
          ),
        ),
      ],
    );
  }
}
