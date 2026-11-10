import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../dominio/disponibilidad_conductores.dart';

/// Tarjeta del aviso de disponibilidad, con el cambio de vehículo de un toque
/// si hay del otro tipo. La usan el detalle de la solicitud y la búsqueda.
class TarjetaAvisoDisponibilidad extends StatelessWidget {
  const TarjetaAvisoDisponibilidad({
    super.key,
    required this.aviso,
    required this.onCambiarVehiculo,
  });

  final AvisoDisponibilidad aviso;

  /// `true` para moto, `false` para carro.
  final ValueChanged<bool>? onCambiarVehiculo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ofrecerMoto = aviso.ofrecerMoto;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColores.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColores.warning.withValues(alpha: 0.4)),
        ),
        // Angosta: texto arriba y el botón debajo a la derecha; apretados en
        // una fila, el mensaje quedaba en tres renglones junto a un botón
        // enorme.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mensaje = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    aviso.critico
                        ? Icons.error_outline_rounded
                        : Icons.access_time_rounded,
                    size: 20,
                    color: AppColores.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    aviso.mensaje,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            );
            if (ofrecerMoto == null || onCambiarVehiculo == null) {
              return mensaje;
            }
            final boton = _BotonCambio(
              moto: ofrecerMoto,
              onPressed: () => onCambiarVehiculo!(ofrecerMoto),
            );
            if (constraints.maxWidth < 330) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [mensaje, const SizedBox(height: 8), boton],
              );
            }
            return Row(
              children: [
                Expanded(child: mensaje),
                const SizedBox(width: 10),
                boton,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Compacto y del mismo alto en cualquier pantalla: es una sugerencia, no la
/// acción principal de la pantalla.
class _BotonCambio extends StatelessWidget {
  const _BotonCambio({required this.moto, required this.onPressed});

  final bool moto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.ink900,
        iconColor: AppColores.ink900,
        minimumSize: const Size(0, 36),
        // 48 de área táctil aunque el botón se vea de 36.
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(
        moto ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
        size: 16,
      ),
      label: Text(
        moto ? 'Pedir moto' : 'Pedir carro',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}
