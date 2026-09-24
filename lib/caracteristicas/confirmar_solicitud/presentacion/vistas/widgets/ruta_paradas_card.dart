import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Recorrido en una sola tarjeta: recogida y destino unidos por una línea
/// punteada, cada uno tocable para ajustarlo (lápiz a la derecha).
class RutaParadasCard extends StatelessWidget {
  const RutaParadasCard({
    super.key,
    required this.origen,
    required this.destino,
    required this.onEditarOrigen,
    required this.onEditarDestino,
  });

  final String origen;
  final String destino;
  final VoidCallback onEditarOrigen;
  final VoidCallback onEditarDestino;

  static const Color _azul = Color(0xFF2F6BFF);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _Parada(
            etiqueta: 'Recogida',
            valor: origen,
            marcador: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _azul,
                shape: BoxShape.circle,
                border: Border.all(color: palette.surface, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: _azul.withValues(alpha: 0.35),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            lineaAbajo: true,
            onTap: onEditarOrigen,
          ),
          Divider(height: 1, indent: 52, color: palette.divider),
          _Parada(
            etiqueta: 'Destino',
            valor: destino,
            marcador: const Icon(
              Icons.location_on_rounded,
              color: AppColores.error,
              size: 22,
            ),
            lineaArriba: true,
            onTap: onEditarDestino,
          ),
        ],
      ),
    );
  }
}

class _Parada extends StatelessWidget {
  const _Parada({
    required this.etiqueta,
    required this.valor,
    required this.marcador,
    required this.onTap,
    this.lineaArriba = false,
    this.lineaAbajo = false,
  });

  final String etiqueta;
  final String valor;
  final Widget marcador;
  final VoidCallback onTap;
  final bool lineaArriba;
  final bool lineaAbajo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      // Alto fijo: cada parada es de una sola línea (ellipsis), y así la
      // línea punteada puede ocupar exactamente el alto sobrante.
      child: SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Columna del marcador con la línea punteada que une las dos
            // paradas (mitad inferior de la primera, mitad superior de la
            // segunda).
            SizedBox(
              width: 52,
              child: Column(
                children: [
                  Expanded(
                    child: lineaArriba
                        ? _LineaPunteada(color: palette.grey400)
                        : const SizedBox.shrink(),
                  ),
                  SizedBox(height: 24, child: Center(child: marcador)),
                  Expanded(
                    child: lineaAbajo
                        ? _LineaPunteada(color: palette.grey400)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.edit_outlined,
                size: 19,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineaPunteada extends StatelessWidget {
  const _LineaPunteada({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PunteadaPainter(color), size: Size.infinite);
}

class _PunteadaPainter extends CustomPainter {
  _PunteadaPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    for (var y = 2.0; y < size.height - 1; y += 6) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 2), paint);
    }
  }

  @override
  bool shouldRepaint(_PunteadaPainter old) => old.color != color;
}
