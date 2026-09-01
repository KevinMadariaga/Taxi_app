import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Muestra el diálogo de bienvenida animado (entrada con escala + fade).
/// Pensado para mostrarse SOLO la primera vez que el usuario inicia sesión.
Future<void> mostrarBienvenida(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Bienvenida',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, _, _) {
      final curva = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.82 + 0.18 * curva.value,
          child: const _ContenidoBienvenida(),
        ),
      );
    },
  );
}

class _ContenidoBienvenida extends StatelessWidget {
  const _ContenidoBienvenida();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              decoration: BoxDecoration(
                color: AppColores.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColores.primary.withValues(alpha: 0.16),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/img/Ride.png',
                        width: 65,
                        height: 65,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '¡Bienvenido a Ride!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      color: AppColores.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Puedes solicitar tu servicio de transporte de '
                    'manera fácil y rápida.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.primary,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Comenzar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
