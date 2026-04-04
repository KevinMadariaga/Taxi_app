import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class DriverWaitingClientModal extends StatelessWidget {
  const DriverWaitingClientModal({
    super.key,
    required this.remainingSeconds,
    required this.canStartTrip,
    required this.isLoading,
    required this.onStartTrip,
  });

  final int remainingSeconds;
  final bool canStartTrip;
  final bool isLoading;
  final VoidCallback onStartTrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      decoration: const BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColores.grey300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'En espera del cliente',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (!canStartTrip) ...[
              Text(
                _format(remainingSeconds),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColores.buttonChat,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              canStartTrip
                  ? 'Cliente confirmado. Ya puedes iniciar la ruta.'
                  : 'Esperando confirmación del cliente (estado en camino).',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColores.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canStartTrip && !isLoading ? onStartTrip : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColores.buttonPrimary,
                  foregroundColor: AppColores.textPrimary,
                  disabledBackgroundColor: AppColores.grey300,
                  disabledForegroundColor: AppColores.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColores.textPrimary,
                        ),
                      )
                    : const Text(
                        'Comenzar ruta',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
