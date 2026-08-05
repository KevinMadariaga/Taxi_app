import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Botón "Aceptar", ancho completo — con spinner mientras
/// `isAcceptLoading`. "Ofertar" ya no vive acá: se muestra flotando sobre
/// el mapa (ver `PreviewSolicitudCard`) para dejarle todo este ancho al CTA
/// principal.
class AccionesSolicitudButtons extends StatelessWidget {
  const AccionesSolicitudButtons({
    super.key,
    required this.isAcceptLoading,
    required this.onAccept,
  });

  final bool isAcceptLoading;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return CustomButton(
      text: 'Aceptar',
      color: AppColores.buttonPrimary,
      textColor: AppColores.textWhite,
      isLoading: isAcceptLoading,
      onPressed: isAcceptLoading ? null : onAccept,
      width: double.infinity,
      height: 56,
      fontSize: 17,
    );
  }
}
