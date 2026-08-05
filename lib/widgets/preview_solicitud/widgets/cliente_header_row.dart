import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Fila superior de la mitad de info: avatar del cliente + nombre + badge
/// de cercanía (verde ≤1km, ámbar si está más lejos, gris si aún no se
/// conoce la distancia).
class ClienteHeaderRow extends StatelessWidget {
  const ClienteHeaderRow({
    super.key,
    required this.nombre,
    required this.photoUrl,
    required this.distanciaKm,
  });

  final String nombre;
  final String? photoUrl;
  final double? distanciaKm;

  @override
  Widget build(BuildContext context) {
    final km = distanciaKm;
    final String cercania;
    final Color badgeColor;
    final Color badgeTextColor;
    final String kmTxt = km != null ? ' · ${km.toStringAsFixed(1)} km' : '';
    if (km != null && km <= 1.0) {
      cercania = 'Cerca$kmTxt';
      badgeColor = AppColores.success.withValues(alpha: 0.12);
      badgeTextColor = AppColores.success;
    } else if (km != null) {
      cercania = 'Lejos$kmTxt';
      badgeColor = AppColores.warning.withValues(alpha: 0.12);
      badgeTextColor = AppColores.warning;
    } else {
      cercania = 'Solicitud cercana';
      badgeColor = AppColores.grey200;
      badgeTextColor = AppColores.textSecondary;
    }

    final tienePhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColores.grey400,
          backgroundImage: tienePhoto ? NetworkImage(photoUrl!) : null,
          child: tienePhoto
              ? null
              : const Icon(Icons.person, color: AppColores.textWhite, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombre.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  cercania,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
