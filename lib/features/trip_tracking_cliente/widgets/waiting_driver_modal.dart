import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

class WaitingDriverModal extends StatelessWidget {
  const WaitingDriverModal({
    super.key,
    required this.remainingSeconds,
    required this.isUpdating,
    required this.onVoyEnCamino,
  });

  final ValueNotifier<int> remainingSeconds;
  final bool isUpdating;
  final Future<void> Function() onVoyEnCamino;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      decoration: BoxDecoration(
        color: context.palette.surface,
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
                color: context.palette.grey300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'El conductor está afuera',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<int>(
              valueListenable: remainingSeconds,
              builder: (context, value, _) {
                return Text(
                  _format(value),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColores.buttonChat,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Tienes 3 minutos para confirmar.',
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isUpdating ? null : onVoyEnCamino,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.buttonPrimary,
                  foregroundColor: context.palette.textPrimary,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isUpdating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.palette.textPrimary,
                        ),
                      )
                    : const Text(
                        'Voy en camino',
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
