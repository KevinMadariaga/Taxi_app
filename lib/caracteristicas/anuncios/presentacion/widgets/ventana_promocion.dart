import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../../dominio/entidades/promocion.dart';

/// Abre la ventana de [promo] en medio de la pantalla, con una entrada
/// suave (sin animación si el sistema pide reducirlas).
Future<void> mostrarVentanaPromocion(BuildContext context, Promocion promo) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar promoción',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => VentanaPromocion(promo: promo),
    transitionBuilder: (context, animacion, _, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      final curva = CurvedAnimation(
        parent: animacion,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: animacion,
        child: ScaleTransition(
          scale: Tween(begin: 0.88, end: 1.0).animate(curva),
          child: child,
        ),
      );
    },
  );
}

/// Ventana de promoción con estilo propio de Ride: tarjeta oscura con arco
/// arriba, la imagen en un círculo con anillo naranja que sobresale, título
/// y texto centrados, botón píldora naranja, franja "PROMO · RIDE" con el
/// degradado de marca y la X redonda debajo de la tarjeta. La tarjeta es
/// oscura en los dos temas (es una pieza de marca, como un afiche).
class VentanaPromocion extends StatelessWidget {
  const VentanaPromocion({super.key, required this.promo});

  final Promocion promo;

  static const Color _fondo = AppColores.ink900;
  static const Color _fondoAlto = AppColores.ink700;
  static const LinearGradient _degradadoMarca = LinearGradient(
    colors: [AppColores.primary, AppColores.brand500],
  );

  @override
  Widget build(BuildContext context) {
    final pantalla = MediaQuery.sizeOf(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: pantalla.height - 48,
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                // El círculo crece con el ancho pero no se come la tarjeta.
                final diametro = (c.maxWidth * 0.56).clamp(150.0, 220.0);
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: diametro * 0.5),
                            child: _Tarjeta(
                              promo: promo,
                              ancho: c.maxWidth,
                              espacioArriba: diametro * 0.5 + 18,
                            ),
                          ),
                          _Circulo(promo: promo, diametro: diametro),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _BotonCerrar(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.promo,
    required this.ancho,
    required this.espacioArriba,
  });

  final Promocion promo;
  final double ancho;
  final double espacioArriba;

  @override
  Widget build(BuildContext context) {
    // Arco: elipse con el ancho de la tarjeta, abajo esquinas suaves.
    final forma = BorderRadius.vertical(
      top: Radius.elliptical(ancho / 2, ancho * 0.32),
      bottom: const Radius.circular(28),
    );
    return Material(
      color: Colors.transparent,
      elevation: 18,
      shadowColor: AppColores.primary.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: forma),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [VentanaPromocion._fondoAlto, VentanaPromocion._fondo],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, espacioArriba, 24, 22),
              child: Column(
                children: [
                  Text(
                    promo.titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: VentanaPromocion._degradadoMarca,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    promo.cuerpo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColores.primary,
                        foregroundColor: AppColores.ink900,
                        padding: const EdgeInsets.symmetric(horizontal: 34),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        '¡Entendido!',
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
            const _Franja(),
          ],
        ),
      ),
    );
  }
}

/// Imagen de la promo en círculo con anillo de marca; sin imagen, el
/// megáfono sobre el degradado.
class _Circulo extends StatelessWidget {
  const _Circulo({required this.promo, required this.diametro});

  final Promocion promo;
  final double diametro;

  @override
  Widget build(BuildContext context) {
    final sinImagen = Container(
      decoration: const BoxDecoration(
        gradient: VentanaPromocion._degradadoMarca,
      ),
      child: Icon(
        Icons.campaign_rounded,
        size: diametro * 0.45,
        color: AppColores.ink900,
      ),
    );
    return Container(
      width: diametro,
      height: diametro,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: VentanaPromocion._degradadoMarca,
        boxShadow: [
          BoxShadow(
            color: AppColores.primary.withValues(alpha: 0.45),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: promo.imagenUrl.isEmpty
            ? sinImagen
            : CachedNetworkImage(
                imageUrl: promo.imagenUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: VentanaPromocion._fondoAlto),
                errorWidget: (_, _, _) => sinImagen,
              ),
      ),
    );
  }
}

/// Franja inferior con el degradado de marca, como una cinta de "novedad".
class _Franja extends StatelessWidget {
  const _Franja();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: VentanaPromocion._degradadoMarca,
      ),
      child: ExcludeSemantics(
        child: Text(
          List.filled(8, 'PROMO  ·  RIDE').join('  ·  '),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: 3,
            fontWeight: FontWeight.w800,
            color: AppColores.ink900,
          ),
        ),
      ),
    );
  }
}

class _BotonCerrar extends StatelessWidget {
  const _BotonCerrar();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 6,
      child: IconButton(
        tooltip: 'Cerrar',
        iconSize: 26,
        constraints: const BoxConstraints.tightFor(width: 52, height: 52),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded, color: AppColores.ink900),
      ),
    );
  }
}
