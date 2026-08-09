import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Izquierda: foto del conductor (grande) + calificación debajo, con el
/// nombre al lado de la foto. Derecha: foto del vehículo + placa/tipo
/// debajo — misma distribución que apps de referencia tipo Uber/DiDi.
class ConductorVehiculoInfo extends StatelessWidget {
  const ConductorVehiculoInfo({
    super.key,
    required this.nombre,
    required this.fotoConductorUrl,
    required this.fotoVehiculoUrl,
    required this.placa,
    required this.calificacion,
    this.isMoto = false,
    this.avatarRadius = 36,
    this.vehiculoWidth = 84,
    this.vehiculoHeight = 60,
  });

  final String nombre;
  final String? fotoConductorUrl;
  final String? fotoVehiculoUrl;
  final String? placa;
  final double calificacion;
  final bool isMoto;

  /// Medidas escaladas por `TripCardMetrics` según el alto de pantalla —
  /// los defaults son las del teléfono estándar.
  final double avatarRadius;
  final double vehiculoWidth;
  final double vehiculoHeight;

  static String _iniciales(String nombre) {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (partes.isEmpty) return '?';
    final primera = partes.first[0];
    final segunda = partes.length > 1 ? partes.last[0] : '';
    return (primera + segunda).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tieneFotoConductor =
        fotoConductorUrl != null && fotoConductorUrl!.isNotEmpty;
    final tieneFotoVehiculo =
        fotoVehiculoUrl != null && fotoVehiculoUrl!.isNotEmpty;
    final tienePlaca = placa != null && placa!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bloque conductor: foto grande, nombre al lado, calificación
        // debajo del nombre (no debajo de la foto).
        CircleAvatar(
          radius: avatarRadius,
          backgroundColor: AppColores.brand200,
          backgroundImage: tieneFotoConductor
              ? NetworkImage(fotoConductorUrl!)
              : null,
          child: tieneFotoConductor
              ? null
              : Text(
                  _iniciales(nombre),
                  style: TextStyle(
                    color: AppColores.brand900,
                    fontWeight: FontWeight.w700,
                    fontSize: avatarRadius * (22 / 36),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.2,
                    color: AppColores.ink900,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: AppColores.warning,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      calificacion.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColores.ink900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Bloque vehículo: foto, placa/tipo debajo — alineado a la derecha.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: vehiculoWidth,
                height: vehiculoHeight,
                color: AppColores.grey100,
                child: tieneFotoVehiculo
                    ? CachedNetworkImage(
                        imageUrl: fotoVehiculoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, _, error) => const Icon(
                          Icons.directions_car_outlined,
                          color: AppColores.textSecondary,
                        ),
                      )
                    : Icon(
                        isMoto
                            ? Icons.two_wheeler_outlined
                            : Icons.directions_car_outlined,
                        color: AppColores.textSecondary,
                      ),
              ),
            ),
            if (tienePlaca) ...[
              const SizedBox(height: 4),
              Text(
                placa!.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColores.ink900,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
