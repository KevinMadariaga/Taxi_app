import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../viewmodels/calificaciones_clientes_viewmodel.dart';

/// "★ 4.8 (12)" con el promedio que los conductores le dieron al cliente.
/// Mientras carga no ocupa espacio; sin calificaciones muestra
/// [textoSinCalificacion] (o nada si es `null`).
class CalificacionClienteBadge extends StatelessWidget {
  const CalificacionClienteBadge({
    super.key,
    required this.clienteId,
    this.textoSinCalificacion = 'Nuevo',
    this.fontSize = 12,
    this.decoracion,
    this.padding = EdgeInsets.zero,
    this.cincoEstrellas = false,
  });

  final String clienteId;
  final String? textoSinCalificacion;
  final double fontSize;

  /// Fondo opcional (ej. pastilla del perfil). Se pinta solo cuando hay algo
  /// que mostrar: mientras carga no queda una pastilla vacía.
  final BoxDecoration? decoracion;
  final EdgeInsetsGeometry padding;

  /// `true`: fila de 5 estrellas llenas/medias/vacías según el promedio (perfil)
  /// en vez de una sola estrella (tarjetas compactas).
  final bool cincoEstrellas;

  Widget _envolver(Widget hijo) {
    final d = decoracion;
    if (d == null) return hijo;
    return Container(padding: padding, decoration: d, child: hijo);
  }

  @override
  Widget build(BuildContext context) {
    final CalificacionesClientesViewModel vm;
    try {
      vm = context.watch<CalificacionesClientesViewModel>();
    } on ProviderNotFoundException {
      // Pantallas montadas sueltas (tests, previews) sin el provider global.
      return const SizedBox.shrink();
    }
    if (!vm.cargado(clienteId)) {
      vm.de(clienteId);
      return const SizedBox.shrink();
    }

    final palette = context.palette;
    final calificacion = vm.de(clienteId);
    if (calificacion == null || !calificacion.tieneCalificaciones) {
      final texto = textoSinCalificacion;
      if (texto == null) return const SizedBox.shrink();
      return _envolver(
        Text(
          texto,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      );
    }

    return _envolver(
      Semantics(
        label:
            'Calificación del cliente ${calificacion.promedio.toStringAsFixed(1)} '
            'de 5, ${calificacion.total} calificaciones',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cincoEstrellas)
              for (var i = 1; i <= 5; i++)
                Icon(
                  calificacion.promedio >= i
                      ? Icons.star_rounded
                      : calificacion.promedio >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
                  size: fontSize + 3,
                  color: AppColores.primary,
                )
            else
              Icon(
                Icons.star_rounded,
                size: fontSize + 3,
                color: AppColores.primary,
              ),
            SizedBox(width: cincoEstrellas ? 6 : 2),
            Text(
              calificacion.promedio.toStringAsFixed(1),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '(${calificacion.total})',
              style: TextStyle(
                fontSize: fontSize,
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
