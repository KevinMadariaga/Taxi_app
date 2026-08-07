import 'package:flutter/material.dart';

import 'package:taxi_app/core/theme/ride_button_styles.dart';

/// Chat / Navegar arriba (ambos [RideSecondaryButton], mismo peso visual),
/// acción primaria (relabeled según fase — "Ya llegué", "Comenzar ruta",
/// "Terminar viaje") abajo como único [RidePrimaryButton] de la pantalla.
/// Puramente presentacional: el label/estado de la acción primaria lo
/// decide `DriverTripCard` a partir del viewmodel, no este widget.
class AccionesConductorButtons extends StatelessWidget {
  const AccionesConductorButtons({
    super.key,
    required this.onChat,
    required this.onNavegar,
    required this.onAccionPrimaria,
    required this.primaryLabel,
    required this.primaryIcon,
    this.mostrarChat = true,
    this.primaryLoading = false,
    this.primaryPastel = false,
  });

  final VoidCallback onChat;
  final VoidCallback onNavegar;
  final VoidCallback? onAccionPrimaria;
  final String primaryLabel;
  final IconData primaryIcon;

  /// El chat solo aplica al tramo de recogida: una vez que el pasajero está a
  /// bordo ("Llévalo a su destino") ya van juntos y escribirse no tiene
  /// sentido. Con `false`, "Navegar" toma el ancho completo.
  final bool mostrarChat;

  final bool primaryLoading;
  final bool primaryPastel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mostrarChat)
          Row(
            children: [
              Expanded(
                child: RideSecondaryButton(
                  text: 'Chat',
                  icon: Icons.chat_bubble_outline,
                  onPressed: onChat,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RideSecondaryButton(
                  text: 'Navegar',
                  icon: Icons.navigation_rounded,
                  onPressed: onNavegar,
                ),
              ),
            ],
          )
        else
          RideSecondaryButton(
            text: 'Navegar',
            icon: Icons.navigation_rounded,
            onPressed: onNavegar,
          ),
        const SizedBox(height: 12),
        RidePrimaryButton(
          text: primaryLabel,
          icon: primaryIcon,
          isLoading: primaryLoading,
          onPressed: onAccionPrimaria,
          pastel: primaryPastel,
        ),
      ],
    );
  }
}
