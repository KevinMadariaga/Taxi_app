import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Fila de ETA/distancia — dos variantes (expandida: texto largo con
/// separador; colapsada: chips con ícono), promovida tal cual desde
/// `UserTripInfoCard`/`DriverClientInfoCard` (pixel-idénticas en ambas
/// tarjetas hoy).
class EtaDistanciaRow extends StatelessWidget {
  const EtaDistanciaRow({
    super.key,
    required this.etaText,
    required this.distanceText,
    required this.expanded,
    this.showLabel = true,
  });

  final String etaText;
  final String distanceText;
  final bool expanded;

  /// `false`: variante expandida sin la etiqueta "Tiempo estimado" —
  /// métrica de una sola línea tipo "1 min · 374 m" (tarjeta del
  /// conductor). `true` (default): mantiene el texto largo original para
  /// no afectar a `trip_info_card.dart` (lado cliente).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      final texto = showLabel
          ? 'Tiempo estimado: $etaText • $distanceText'
          : '$etaText · $distanceText';
      return Text(
        texto,
        style: const TextStyle(color: AppColores.ink500, fontSize: 12),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.schedule_rounded, size: 16, color: AppColores.ink500),
        const SizedBox(width: 4),
        Text(
          etaText,
          style: const TextStyle(
            color: AppColores.ink700,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 16),
        const Icon(Icons.route_outlined, size: 16, color: AppColores.ink500),
        const SizedBox(width: 4),
        Text(
          distanceText,
          style: const TextStyle(
            color: AppColores.ink700,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
