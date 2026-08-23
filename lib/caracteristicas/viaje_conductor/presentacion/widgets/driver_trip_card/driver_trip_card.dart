import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/trip_card_metrics.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/widgets/barra_progreso_direccional.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/widgets/eta_distancia_row.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/viewmodels/viaje_conductor_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/theme/ride_button_styles.dart';

import 'widgets/acciones_conductor_buttons.dart';
import 'widgets/cliente_header_row.dart';

/// LA tarjeta del conductor: reemplaza `DriverClientInfoCard`. Orquestador
/// delgado sobre sub-widgets (mismo criterio que
/// `lib/widgets/preview_solicitud/preview_solicitud_card.dart`) — escucha
/// el viewmodel directamente vía `AnimatedBuilder` en vez de recibir dos
/// docenas de props sueltas.
///
/// Siempre muestra el contenido completo — sin colapsar/expandir. Su alto lo
/// decide su propio contenido, escalado por `TripCardMetrics` según el alto
/// de pantalla (ver `ViajeConductorScreen`, mismo modelo que
/// `TripInfoCard` del lado cliente).
class DriverTripCard extends StatefulWidget {
  const DriverTripCard({
    super.key,
    required this.vm,
    required this.onChat,
    required this.onDetails,
    required this.onReportarLlegada,
    required this.onComenzarRuta,
    required this.onTerminarViaje,
  });

  final ViajeConductorViewModel vm;
  final VoidCallback onChat;
  final VoidCallback onDetails;
  final VoidCallback onReportarLlegada;
  final VoidCallback onComenzarRuta;
  final VoidCallback onTerminarViaje;

  @override
  State<DriverTripCard> createState() => _DriverTripCardState();
}

class _DriverTripCardState extends State<DriverTripCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.vm.progresoTramo.clamp(0.0, 1.0),
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    );
    widget.vm.addListener(_syncProgress);
  }

  void _syncProgress() {
    final target = widget.vm.progresoTramo.clamp(0.0, 1.0);
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

  ({String label, IconData icon, VoidCallback? onTap, bool pastel})
  _accionPrimaria(ViajeConductorViewModel vm) {
    final estado = vm.viaje?.estado;
    if (estado == SolicitudEstado.enEspera) {
      return (
        label: 'Esperando confirmación...',
        icon: Icons.hourglass_top_rounded,
        onTap: null,
        pastel: false,
      );
    }
    if (estado == SolicitudEstado.enCamino) {
      return (
        label: 'Comenzar ruta',
        icon: Icons.route_rounded,
        onTap: widget.onComenzarRuta,
        pastel: false,
      );
    }
    if (estado == SolicitudEstado.enRuta) {
      return (
        label: 'Terminar viaje',
        icon: Icons.flag_rounded,
        onTap: widget.onTerminarViaje,
        pastel: false,
      );
    }
    // Estados terminales: el viaje ya cerró y la pantalla está saliendo (la
    // navegación va en un post-frame). Sin este caso caían al fallthrough de
    // "Ya llegué al punto" HABILITADO, con una ventana de un frame para
    // escribir `en espera` sobre un viaje ya completado o cancelado.
    if (estado != null && SolicitudEstado.isTerminal(estado)) {
      return (
        label: 'Viaje finalizado',
        icon: Icons.check_circle_outline_rounded,
        onTap: null,
        pastel: false,
      );
    }
    // asignado (o cualquier otro): reportar llegada, solo dentro del radio.
    final dentroDeRango = vm.puedeReportarLlegada;
    return (
      label: vm.hasReportedArrival
          ? 'Enviado'
          : (dentroDeRango
                ? 'Ya llegué al punto'
                : 'Acércate para reportar llegada'),
      icon: vm.hasReportedArrival ? Icons.check : Icons.my_location_rounded,
      onTap: (vm.hasReportedArrival || !dentroDeRango)
          ? null
          : widget.onReportarLlegada,
      pastel: true,
    );
  }

  String _titulo(ViajeConductorViewModel vm) {
    switch (vm.tramoActual) {
      case TramoViajeConductor.recogida:
        return 'Recoge al cliente';
      case TramoViajeConductor.destino:
        return 'Llévalo a su destino';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) {
        final vm = widget.vm;
        final accion = _accionPrimaria(vm);
        final m = TripCardMetrics.of(context);

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: m.paddingVertical),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: m.gapSuperior),
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
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColores.brand900,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: m.gapTitulo),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ClienteHeaderRow(
                        nombre: vm.clienteNombre,
                        photoUrl: vm.clientePhotoUrl,
                        direccion: vm.clienteDireccion,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RidePillButton(
                      text: 'Detalles',
                      onPressed: widget.onDetails,
                    ),
                  ],
                ),
                SizedBox(height: m.gapSeccion),
                EtaDistanciaRow(
                  etaText: vm.etaText,
                  distanceText: vm.distanceText,
                  expanded: true,
                  showLabel: false,
                ),
                SizedBox(height: m.gapSeccion),
                BarraProgresoDireccional(
                  animation: _progressAnimation,
                  isMoto: vm.isMoto,
                  // Conserva la proporción "ride" (38/44) escalando por
                  // franja de pantalla en vez de un tamaño fijo.
                  circleSize: m.barraCircleSize * (38 / 44),
                  destinoIcon: Icons.place_outlined,
                  vehicleIconRatio: 30 / 44,
                ),
                SizedBox(height: m.gapCompacto),
                AccionesConductorButtons(
                  onChat: widget.onChat,
                  onNavegar: vm.abrirNavegacionExterna,
                  onAccionPrimaria: accion.onTap,
                  primaryLabel: accion.label,
                  primaryIcon: accion.icon,
                  chatBadgeCount: vm.chat.unreadCount,
                  // El chat solo en el tramo de recogida: ya con el pasajero a
                  // bordo van juntos en el vehículo.
                  mostrarChat: vm.tramoActual == TramoViajeConductor.recogida,
                  primaryLoading:
                      vm.isSendingArrival ||
                      vm.isValidatingCodigo ||
                      vm.isFinalizandoViaje,
                  primaryPastel: accion.pastel,
                ),
                // Sin botón de cancelar: por diseño del negocio, el viaje lo
                // cancela el CLIENTE. El conductor escucha ese cambio de
                // estado en Firestore y sale solo — `_handleEstadoTransition`
                // pone `debeSalir` al ver `cancelado` y la pantalla navega de
                // vuelta a `InicioConductor` con el motivo.
              ],
            ),
          ),
        );
      },
    );
  }
}
