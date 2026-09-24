import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/notificaciones_view.dart';

/// Notificaciones del conductor: misma pantalla que la del cliente con sus
/// interruptores (y sus claves de preferencias).
class NotificacionesConductorView extends StatelessWidget {
  const NotificacionesConductorView({super.key});

  @override
  Widget build(BuildContext context) =>
      const NotificacionesView(opciones: opcionesNotificacionConductor);
}
