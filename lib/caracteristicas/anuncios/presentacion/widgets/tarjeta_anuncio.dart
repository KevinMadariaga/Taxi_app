import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// La tarjeta de un anuncio tal como sale en el carrusel del inicio. La
/// usan el carrusel y la vista previa del editor del admin, así lo que se
/// ve antes de subir es exactamente lo que verán los pasajeros.
class TarjetaAnuncio extends StatelessWidget {
  const TarjetaAnuncio({
    super.key,
    required this.imagen,
    this.conDetalle = false,
    this.onTap,
  });

  final Widget imagen;

  /// Muestra la pastilla "Ver detalle" (el anuncio tiene texto o enlaces).
  final bool conDetalle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imagen,
            if (conDetalle)
              const Positioned(left: 10, bottom: 10, child: _PastillaDetalle()),
          ],
        ),
      ),
    );
  }
}

class _PastillaDetalle extends StatelessWidget {
  const _PastillaDetalle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: AppColores.ink900.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ver detalle',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColores.primary,
          ),
        ],
      ),
    );
  }
}
