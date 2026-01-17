import 'package:flutter/material.dart';

/// Muestra un loader centrado como diálogo sin barra de título.
/// El loader permanece [visibleDuration] y luego se desvanece en [fadeDuration].
Future<void> showFloatingLoader(
  BuildContext context, {
  Duration visibleDuration = const Duration(seconds: 1),
  Duration fadeDuration = const Duration(milliseconds: 400),
}) async {
  // Programar el cierre automático
  final popDelay = visibleDuration + fadeDuration;

  // Capture the context so we can check mounted before using it in async callbacks.
  final BuildContext ctx = context;

  // Usamos showGeneralDialog para controlar la transición (fade)
  final future = showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Cargando',
    transitionDuration: fadeDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const SizedBox.shrink(); // construido en transitionBuilder
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      );
    },
  );

  // Cerrar el diálogo automáticamente después del tiempo combinado
  Future.delayed(popDelay, () {
    if (!ctx.mounted) return;
    if (Navigator.of(ctx, rootNavigator: true).canPop()) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  });

  // Esperar hasta que el diálogo se cierre
  await future;
}
