import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class TripRouteStatusCard extends StatelessWidget {
  const TripRouteStatusCard({
    super.key,
    required this.etaText,
    required this.distanceText,
    required this.isOffline,
    required this.isSyncingPending,
  });

  final String etaText;
  final String distanceText;
  final bool isOffline;
  final bool isSyncingPending;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_filled, color: AppColores.primary),
            const SizedBox(width: 6),
            Text(
              etaText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            const Icon(Icons.route, color: AppColores.primary),
            const SizedBox(width: 6),
            Text(
              distanceText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColores.textPrimary,
              ),
            ),
            if (isOffline || isSyncingPending) ...[
              const SizedBox(width: 14),
              Icon(
                isOffline ? Icons.wifi_off_rounded : Icons.sync,
                color: isOffline ? AppColores.warning : AppColores.buttonChat,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
