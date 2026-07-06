import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/core/app_colores.dart';

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
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColores.textSecondary),
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      final uri = Uri.parse('tel:123');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'panic_button',
      backgroundColor: AppColores.error,
      onPressed: _confirmarLlamada,
      tooltip: 'Llamar al 123 — Emergencias',
      child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 26),
    );
  }
}
