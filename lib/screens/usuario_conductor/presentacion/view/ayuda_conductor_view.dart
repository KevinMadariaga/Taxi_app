import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda_view.dart';

/// Ayuda del conductor: misma pantalla que la del cliente con sus preguntas.
class AyudaConductorView extends StatelessWidget {
  const AyudaConductorView({super.key});

  @override
  Widget build(BuildContext context) =>
      const AyudaView(preguntas: preguntasConductor, userType: 'conductor');
}
