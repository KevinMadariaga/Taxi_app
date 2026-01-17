import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class SuccessOverlay {
  /// Muestra un overlay centrado con una animación de entrada y se elimina
  /// automáticamente tras [duration].
  static Future<void> show(
    BuildContext context, {
    String message = 'Operación completada',
    Duration duration = const Duration(milliseconds: 1400),
    IconData icon = Icons.check_circle,
    Color iconColor = Colors.green,
  }) async {
    final overlay = OverlayEntry(
      builder: (context) {
        return Material(
          color: Colors.black45,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 450),
              builder: (context, scale, child) {
                final opacity = ((scale - 0.6) / (1.0 - 0.6)).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: iconColor, size: 64),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Insert overlay next frame (safe null check)
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Overlay.of(context).insert(overlay);
    });

    await Future.delayed(duration);
    overlay.remove();
  }
}
