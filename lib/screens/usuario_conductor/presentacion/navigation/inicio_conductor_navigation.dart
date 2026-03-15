import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/historial_viaje_conductor.dart';
import 'package:taxi_app/widgets/perfil.dart';

class InicioConductorNavigation {
  static Future<void> irARutaConductor(
    BuildContext context,
    String idSolicitud,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RutaConductor(idSolicitud: idSolicitud),
      ),
    );
  }

  static Future<void> irAHistorialConductor(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistorialConductor()));
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
