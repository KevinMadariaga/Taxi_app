import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/viewmodels/viaje_cliente_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/widgets/barra_progreso_direccional.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/widgets/eta_distancia_row.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/ride_button_styles.dart';

import 'widgets/codigo_verificacion_banner.dart';
import 'widgets/conductor_vehiculo_info.dart';

/// LA tarjeta del cliente: reemplaza `UserTripInfoCard`. Orquestador
/// delgado, mismo criterio que `DriverTripCard` — escucha el viewmodel
/// directamente vía `AnimatedBuilder`.
///
/// Siempre muestra el contenido completo — sin colapsar/expandir, ocupa la
/// mitad superior fija de la pantalla (ver `ViajeClienteScreen`).
class TripInfoCard extends StatefulWidget {
  const TripInfoCard({
    super.key,
    required this.vm,
    required this.onChat,
    required this.onDetails,
    required this.onHelp,
    required this.onCancel,
    this.onEmergency,
  });

  final ViajeClienteViewModel vm;
  final VoidCallback onChat;
  final VoidCallback onDetails;
  final VoidCallback onHelp;
  final VoidCallback onCancel;
  final VoidCallback? onEmergency;

  @override
  State<TripInfoCard> createState() => _TripInfoCardState();
}

class _TripInfoCardState extends State<TripInfoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.vm.pickupProgress.clamp(0.0, 1.0),
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    );
    widget.vm.addListener(_syncProgress);
  }

  void _syncProgress() {
    final target = widget.vm.pickupProgress.clamp(0.0, 1.0);
    if ((target - _progressController.value).abs() > 0.001) {
      _progressController.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_syncProgress);
    _progressController.dispose();
    super.dispose();
  }

  String _titulo(ViajeClienteViewModel vm) {
    final estado = vm.viaje?.estado;
    if (estado == 'en camino') return 'Vas en camino al vehículo';
    return 'Conductor llegando a tu ubicación';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) {
        final vm = widget.vm;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColores.cardBackground,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColores.brand50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _titulo(vm),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColores.brand900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                CodigoVerificacionBanner(viajeId: vm.viajeId),
                const SizedBox(height: 10),
                ConductorVehiculoInfo(
                  nombre: vm.conductorNombre,
                  fotoConductorUrl: vm.conductorFotoUrl,
                  fotoVehiculoUrl: vm.vehiculoFotoUrl,
                  placa: vm.placaVehiculo,
                  calificacion: vm.calificacionConductor,
                  isMoto: vm.isMoto,
                ),
                const SizedBox(height: 8),
                EtaDistanciaRow(
                  etaText: vm.etaText,
                  distanceText: vm.distanceText,
                  expanded: true,
                  showLabel: false,
                ),
                const SizedBox(height: 10),
                BarraProgresoDireccional(
                  animation: _progressAnimation,
                  isMoto: vm.isMoto,
                  vehicleIconRatio: 24 / 44,
                ),
                const SizedBox(height: 14),
                if (widget.onEmergency != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onEmergency,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColores.danger,
                        side: const BorderSide(
                          color: AppColores.danger,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.emergency_rounded,
                        size: 18,
                        color: AppColores.danger,
                      ),
                      label: const Text(
                        'Llamar emergencia',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColores.danger,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: RideSecondaryButton(
                        text: 'Chat',
                        icon: Icons.chat_bubble_outline,
                        onPressed: widget.onChat,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RideSecondaryButton(
                        text: 'Ayuda',
                        icon: Icons.help_outline,
                        onPressed: widget.onHelp,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
