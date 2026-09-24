import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_view.dart';

/// Soporte del conductor: misma pantalla que la del cliente.
class SoporteConductorView extends StatelessWidget {
  const SoporteConductorView({super.key});

  @override
  Widget build(BuildContext context) =>
      const SoporteView(userType: 'conductor');
}
