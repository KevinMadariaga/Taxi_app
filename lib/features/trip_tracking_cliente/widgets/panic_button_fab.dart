import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

class PanicButtonFab extends StatefulWidget {
  const PanicButtonFab({super.key});

  @override
  State<PanicButtonFab> createState() => _PanicButtonFabState();
}

class _PanicButtonFabState extends State<PanicButtonFab> {
  Future<void> _confirmarLlamada() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColores.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_in_talk_rounded,
                color: AppColores.error,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Llamar a emergencias',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Deseas llamar al 123 (Policía Nacional de Colombia)?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: context.palette.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColores.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Llamar al 123',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final uri = Uri.parse('tel:123');
    // Sin fallback antes: si `canLaunchUrl` daba `false` (Android 11+ sin la
    // entrada de `<queries>` para ACTION_DIAL — ver AndroidManifest.xml,
    // ahora corregido) el botón SOS no hacía absolutamente nada, en silencio,
    // justo cuando el usuario está en peligro (auditoría de bugs). Ahora se
    // intenta igual y, si falla, se muestra el número para marcarlo a mano.
    bool lanzado = false;
    try {
      lanzado = await launchUrl(uri);
    } catch (_) {
      lanzado = false;
    }
    if (!lanzado && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el marcador. Llama manualmente al 123.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Llamar al 123 — Emergencias',
      child: Material(
        color: AppColores.danger,
        shape: const CircleBorder(),
        elevation: 6,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _confirmarLlamada,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                'SOS',
                style: TextStyle(
                  color: AppColores.textWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
