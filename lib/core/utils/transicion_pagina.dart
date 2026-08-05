import 'package:flutter/material.dart';

/// Transición suave genérica (fade + leve deslizamiento) para navegación
/// entre pantallas dentro de un mismo flujo — más discreta que
/// [transicionInicioCliente], sin escala, pensada para pushes frecuentes
/// (ajustar ubicación, ir a confirmar solicitud, etc.).
///
/// Única fuente: antes vivía duplicada byte a byte como `_buildSmoothRoute`
/// en `InicioClienteNavigation` y en la vista de "Confirmar solicitud".
PageRouteBuilder<T> transicionSuave<T>(Widget pagina) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => pagina,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Transición profesional para entrar a la pantalla principal del cliente
/// tras iniciar sesión: fade + leve desplazamiento hacia arriba + escala
/// sutil. Da una sensación fluida y moderna, típica de apps de transporte,
/// evitando el corte brusco del slide horizontal por defecto.
Route<T> transicionInicioCliente<T>(Widget pagina) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (_, _, _) => pagina,
    transitionsBuilder: (_, animation, _, child) {
      final curva = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curva,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curva),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(curva),
            child: child,
          ),
        ),
      );
    },
  );
}
