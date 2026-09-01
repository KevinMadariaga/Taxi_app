import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Contenido visual del aviso de "sin conexión a internet". Se monta como
/// `OverlayEntry` directamente sobre el `Overlay` raíz (ver
/// `ConectividadGate`), **no** como ruta de `Navigator` — un diálogo normal
/// (`showGeneralDialog`) es una ruta más en el mismo stack que usa el resto
/// de la app para navegar: un `Navigator.pushReplacement` en cualquier otro
/// punto del arranque (p. ej. `InitialScreenResolver` resolviendo la
/// pantalla inicial) reemplaza lo que esté arriba del stack en ese momento
/// — si era este diálogo, lo hacía desaparecer y revelaba la pantalla de
/// abajo (`CompleteProfilePage`) sin que la conexión hubiera vuelto de
/// verdad. Un `OverlayEntry` vive por fuera de ese stack: ninguna
/// navegación por rutas puede quitarlo — solo `ConectividadGate` lo retira,
/// y solo cuando la conectividad real vuelve.
class SinConexionOverlay extends StatelessWidget {
  const SinConexionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x8C000000)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              builder: (context, t, child) {
                final valor = t.clamp(0.0, 1.0);
                return Opacity(
                  opacity: valor,
                  child: Transform.scale(
                    scale: 0.82 + 0.18 * valor,
                    child: child,
                  ),
                );
              },
              child: const _Tarjeta(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta();

  @override
  Widget build(BuildContext context) {
    return Material(
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
                  color: AppColores.warning.withValues(alpha: 0.16),
                ),
                child: const Center(
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 36,
                    color: AppColores.warning,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sin conexión a internet',
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
                'No pudimos conectar con internet. Conéctate a una red '
                'y esta pantalla se cerrará sola, o reinicia la '
                'aplicación si el problema sigue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColores.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
