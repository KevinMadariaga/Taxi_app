import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Barra "vehículo → destino" que se llena según el progreso real (0..1)
/// del viaje — ícono del vehículo a la izquierda, línea de relleno, ícono
/// de destino a la derecha.
///
/// Unifica los dos `_DirectionalBar` que existían duplicados: el del lado
/// cliente (`UserTripInfoCard`) ya estaba atado a progreso real; el del
/// lado conductor (`DriverClientInfoCard`) era un shimmer decorativo en
/// loop, sin relación con la posición real. Se promueve la versión
/// data-driven del cliente para ambos roles — el conductor pasa su propio
/// progreso real (distancia recorrida / distancia inicial de la ruta
/// vigente), mismo cálculo que ya usa el lado cliente.
class BarraProgresoDireccional extends StatelessWidget {
  const BarraProgresoDireccional({
    super.key,
    required this.animation,
    this.isMoto = false,
    this.circleSize = 44,
    this.destinoIcon = Icons.person_outline_rounded,
    this.vehicleIconRatio = 38 / 44,
  });

  final Animation<double> animation;
  final bool isMoto;

  /// Diámetro de los dos círculos (vehículo/destino) — default 44
  /// preserva el tamaño histórico (lado cliente); la tarjeta "Recoge al
  /// cliente" del conductor pasa 26 según el sistema de color "ride".
  final double circleSize;

  /// Ícono del círculo derecho — default persona (lado cliente, hoy
  /// referencia al conductor). El conductor pasa `Icons.place_outlined`
  /// (referencia al punto/destino, no a una persona).
  final IconData destinoIcon;

  /// Fracción del ícono del vehículo respecto a `circleSize` — default
  /// 38/44 (tamaño pedido para "Recoge al cliente"). El lado cliente pasa
  /// una fracción menor.
  final double vehicleIconRatio;

  @override
  Widget build(BuildContext context) {
    final vehicleIconSize = circleSize * vehicleIconRatio;
    final destinoIconSize = circleSize * (30 / 44);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return SizedBox(
          height: circleSize,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: circleSize,
                height: circleSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColores.brand400,
                ),
                child: Icon(
                  isMoto
                      ? Icons.two_wheeler_rounded
                      : Icons.directions_car_filled_rounded,
                  color: AppColores.textWhite,
                  size: vehicleIconSize,
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: circleSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColores.ink200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          // 0.08 mínimo: siempre se ve un tramo junto al
                          // ícono del vehículo aunque el progreso real sea 0.
                          widthFactor: (0.08 + animation.value * 0.92).clamp(
                            0.0,
                            1.0,
                          ),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: AppColores.brand400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColores.surface,
                  border: Border.all(color: AppColores.ink200, width: 0.5),
                ),
                child: Icon(
                  destinoIcon,
                  color: AppColores.ink500,
                  size: destinoIconSize,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
