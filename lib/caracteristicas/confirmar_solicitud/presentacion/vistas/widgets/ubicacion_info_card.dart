import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';

/// Tarjeta tappable de ubicación (usada para "Tu ubicación actual" y
/// "¿Adónde va?"): ícono con badge circular + header + valor.
class UbicacionInfoCard extends StatelessWidget {
  const UbicacionInfoCard({
    super.key,
    required this.header,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBorderColor,
    required this.cardBorderColor,
    required this.cardBorderRadius,
    required this.onTap,
    this.iconBackgroundColor,
  });

  final String header;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBorderColor;
  final Color cardBorderColor;
  final double cardBorderRadius;
  final VoidCallback onTap;

  /// Si se pasa, el badge del ícono se rellena por completo con este color
  /// (sin borde) en vez del estilo por defecto (fondo blanco + borde de
  /// [iconBorderColor]).
  final Color? iconBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(cardBorderRadius);
    return Material(
      color: AppColores.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      // `InkWell` (no `GestureDetector`) para que el splash arranque en el
      // tap-down: sin feedback visual inmediato el tap se sentía "lento"
      // aunque la modal abriera en el mismo tiempo — la percepción de
      // velocidad depende de la respuesta táctil, no solo de la animación.
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 2),
            vertical: ResponsiveHelper.hp(context, 0.8),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: cardBorderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: ResponsiveHelper.wp(context, 11),
                height: ResponsiveHelper.wp(context, 11),
                padding: EdgeInsets.all(ResponsiveHelper.wp(context, 1.6)),
                decoration: BoxDecoration(
                  color: iconBackgroundColor ?? Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: iconBorderColor),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: ResponsiveHelper.wp(context, 6),
                ),
              ),
              SizedBox(width: ResponsiveHelper.wp(context, 3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      header,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.sp(context, 12),
                        color: AppColores.textPrimary,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: ResponsiveHelper.sp(context, 14),
                        color: AppColores.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
