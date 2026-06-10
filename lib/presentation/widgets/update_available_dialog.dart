import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/update_service.dart';

enum UpdateDialogAction { updateNow, later }

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, required this.result});

  final UpdateCheckResult result;

  static Future<UpdateDialogAction?> show(
    BuildContext context,
    UpdateCheckResult result,
  ) {
    return showDialog<UpdateDialogAction>(
      context: context,
      barrierDismissible: result.canSkip,
      builder: (_) => PopScope(
        canPop: result.canSkip,
        child: UpdateAvailableDialog(result: result),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: AppColores.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColores.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.system_update_alt_rounded,
                color: Color(0xFFB38F00),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nueva actualización',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Hay una nueva versión de la app con mejoras de rendimiento, estabilidad y seguridad.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4A5668),
                height: 1.4,
              ),
            ),
            if (result.storeVersion != null) ...[
              const SizedBox(height: 10),
              Text(
                'Versión disponible: ${result.storeVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5F6E84),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (result.isMandatory &&
                result.minimumRequiredVersion != null) ...[
              const SizedBox(height: 4),
              Text(
                'Esta actualización es obligatoria para continuar (mínimo ${result.minimumRequiredVersion}).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB42318),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (result.canSkip)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(UpdateDialogAction.later),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Color(0xFFD0D7E2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Más tarde'),
                    ),
                  ),
                if (result.canSkip) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(UpdateDialogAction.updateNow),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColores.primary,
                      foregroundColor: AppColores.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Actualizar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
