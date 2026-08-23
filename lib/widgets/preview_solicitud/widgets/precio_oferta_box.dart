import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    this.compact = false,
  });

  final double valorCliente;
  final double? valorContraoferta;
  final bool compact;

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
      padding: EdgeInsets.all(compact ? 10.w : 14.w),
      decoration: BoxDecoration(
        color: AppColores.background,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: valorContra == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Valor del servicio',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: (compact ? 12 : 13).sp,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '\$${_formatCurrency(valorCliente)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: (compact ? 18 : 22).sp,
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
                      valorFontSize: (compact ? 14 : 17).sp,
                      strikethrough: true,
                      compact: compact,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 8.w : 12.w),
                    child: const VerticalDivider(
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
                      valorFontSize: (compact ? 18 : 22).sp,
                      icon: Icons.local_offer_outlined,
                      compact: compact,
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
    this.compact = false,
  });

  final String label;
  final double valor;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;
  final Color valorColor;
  final double valorFontSize;
  final IconData? icon;
  final bool strikethrough;
  final bool compact;

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
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: (compact ? 11 : 12).sp,
              color: AppColores.textSecondary,
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14.sp, color: AppColores.primaryDark),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  label,
                  textAlign: textAlign,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: (compact ? 11 : 12).sp,
                    color: AppColores.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: 4.h),
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
