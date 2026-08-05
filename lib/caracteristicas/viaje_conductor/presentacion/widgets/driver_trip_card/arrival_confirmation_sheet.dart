import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Confirmación explícita antes de reportar "Ya llegué al punto" — antes
/// era un tap sin confirmar sobre el botón principal de la tarjeta.
class ArrivalConfirmationSheet extends StatelessWidget {
  const ArrivalConfirmationSheet({super.key});

  static Future<bool?> mostrar(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const ArrivalConfirmationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColores.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Icon(
            Icons.my_location_rounded,
            color: AppColores.success,
            size: 36,
          ),
          const SizedBox(height: 10),
          const Text(
            '¿Confirmas que llegaste al punto de recogida?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppColores.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Se le avisará al cliente que ya estás esperándolo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColores.textSecondary),
          ),
          const SizedBox(height: 18),
          CustomButton(
            text: 'Sí, ya llegué',
            color: AppColores.success,
            onPressed: () => Navigator.of(context).pop(true),
            width: double.infinity,
            height: 50,
          ),
          const SizedBox(height: 10),
          CustomButton(
            text: 'Todavía no',
            color: AppColores.surface,
            textColor: AppColores.textPrimary,
            borderColor: AppColores.borderSubtle,
            onPressed: () => Navigator.of(context).pop(false),
            width: double.infinity,
            height: 46,
          ),
        ],
      ),
    );
  }
}
