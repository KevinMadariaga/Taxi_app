import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class DriverTopStatusCard extends StatelessWidget {
  const DriverTopStatusCard({
    super.key,
    required this.distanceText,
    required this.etaText,
  });

  final String distanceText;
  final String etaText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppColores.borderSubtle,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route, color: AppColores.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            distanceText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColores.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          const Icon(
            Icons.access_time_filled,
            color: AppColores.buttonChat,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            etaText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColores.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
