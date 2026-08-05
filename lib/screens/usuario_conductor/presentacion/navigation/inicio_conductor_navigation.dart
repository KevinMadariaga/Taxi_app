import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/configuracion_aplicacion_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/ayuda_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/comentarios_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/notificaciones_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/seguridad_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/soporte_conductor_view.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/vistas/viaje_conductor_screen.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/historial_viaje_conductor.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/screens/perfil/perfil.dart';

class InicioConductorNavigation {
  static Future<void> irARutaConductor(
    BuildContext context,
    String idSolicitud,
  ) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => IntermediateTransitionView(
          delay: const Duration(seconds: 2),
          title: 'Servicio aceptado',
          subtitle: 'Abriendo ruta hacia el cliente...',
          nextBuilder: (_) => ViajeConductorScreen(viajeId: idSolicitud),
          icon: Icons.local_taxi,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  static Future<void> irAHistorialConductor(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistorialConductor()));
  }

  static Future<void> irAConfiguracion(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracionAplicacionView()),
    );
  }

  static Future<void> irASeguridad(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SeguridadConductorView()));
  }

  static Future<void> irAAyuda(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AyudaConductorView()));
  }

  static Future<void> irASoporte(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SoporteConductorView()));
  }

  static Future<void> irANotificaciones(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificacionesConductorView()),
    );
  }

  static Future<void> irAComentarios(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ComentariosConductorView()));
  }

  static Future<void> irAPerfilConductor(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PaginaPerfilUsuario(tipoUsuario: 'conductor'),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
