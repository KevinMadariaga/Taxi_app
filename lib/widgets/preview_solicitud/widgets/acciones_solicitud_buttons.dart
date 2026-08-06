import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    this.compact = false,
  });

  final bool isAcceptLoading;
  final VoidCallback onAccept;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CustomButton(
      text: 'Aceptar',
      color: AppColores.buttonPrimary,
      textColor: AppColores.textWhite,
      isLoading: isAcceptLoading,
      onPressed: isAcceptLoading ? null : onAccept,
      width: double.infinity,
      height: (compact ? 46 : 56).h,
      fontSize: (compact ? 15 : 17).sp,
    );
  }
}
