import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/seguridad_view.dart';

/// Seguridad del conductor: misma pantalla que la del cliente.
class SeguridadConductorView extends StatelessWidget {
  const SeguridadConductorView({super.key});

  @override
  Widget build(BuildContext context) =>
      const SeguridadView(userType: 'conductor');
}
