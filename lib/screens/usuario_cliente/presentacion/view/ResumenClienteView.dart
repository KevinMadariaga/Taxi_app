import 'package:flutter/material.dart';
import 'package:taxi_app/features/resumen_viaje/controllers/resumen_viaje_controller.dart';
import 'package:taxi_app/features/resumen_viaje/screens/resumen_viaje_view.dart';

class ResumenClienteView extends StatelessWidget {
  const ResumenClienteView({super.key, required this.solicitudId});

  final String solicitudId;

  @override
  Widget build(BuildContext context) {
    return ResumenViajeView(
      tipoUsuario: TipoUsuarioResumen.cliente,
      solicitudId: solicitudId,
    );
  }
}
