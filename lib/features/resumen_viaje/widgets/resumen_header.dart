import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class ResumenHeader extends StatelessWidget {
  const ResumenHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Icon(
          Icons.check_circle_rounded,
          color: AppColores.success,
          size: 68,
        ),
        SizedBox(height: 8),
        Text(
          'Viaje completado',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColores.textPrimary,
          ),
        ),
      ],
    );
  }
}
