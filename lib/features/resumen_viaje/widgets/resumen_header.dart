import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class ResumenHeader extends StatelessWidget {
  const ResumenHeader({
    super.key,
    this.subtitle = 'Gracias por viajar con Taxi Ya',
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColores.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppColores.success,
            size: 56,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '¡Viaje completado!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColores.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColores.textSecondary,
          ),
        ),
      ],
    );
  }
}
