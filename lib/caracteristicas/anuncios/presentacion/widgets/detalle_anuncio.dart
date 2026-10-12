import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../dominio/entidades/anuncio.dart';
import '../../dominio/enlaces_anuncio.dart';

/// Ventana con el detalle de un anuncio del carrusel: imagen, título,
/// texto y los botones para escribirle al negocio por WhatsApp o ver su
/// Instagram. Se cierra con la X de abajo o tocando afuera.
Future<void> mostrarDetalleAnuncio(BuildContext context, Anuncio anuncio) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar anuncio',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => DetalleAnuncio(anuncio: anuncio),
    transitionBuilder: (context, a, _, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.92,
            end: 1.0,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

class DetalleAnuncio extends StatelessWidget {
  const DetalleAnuncio({super.key, required this.anuncio});

  final Anuncio anuncio;

  static const _verdeWhatsApp = Color(0xFF25D366);
  static const _degradadoInstagram = LinearGradient(
    colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
  );

  Future<void> _abrir(BuildContext context, Uri? uri, String app) async {
    final ok =
        uri != null &&
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir $app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final whatsapp = enlaceWhatsApp(
      anuncio.whatsapp,
      mensaje: 'Hola, vi su anuncio en Ride.',
    );
    final instagram = enlaceInstagram(anuncio.instagram);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: palette.surface,
                    elevation: 12,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: kProporcionAnuncio,
                          child: CachedNetworkImage(
                            imageUrl: anuncio.imagenUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                ColoredBox(color: palette.grey100),
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: palette.grey100),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (anuncio.titulo.isNotEmpty)
                                Text(
                                  anuncio.titulo,
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              if (anuncio.detalle.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  anuncio.detalle,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.45,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                              if (whatsapp != null) ...[
                                const SizedBox(height: 18),
                                _BotonContacto(
                                  icono: Icons.chat_rounded,
                                  texto: 'Escribir por WhatsApp',
                                  color: _verdeWhatsApp,
                                  onTap: () =>
                                      _abrir(context, whatsapp, 'WhatsApp'),
                                ),
                              ],
                              if (instagram != null) ...[
                                const SizedBox(height: 10),
                                _BotonContacto(
                                  icono: Icons.camera_alt_rounded,
                                  texto: 'Ver en Instagram',
                                  degradado: _degradadoInstagram,
                                  onTap: () =>
                                      _abrir(context, instagram, 'Instagram'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 6,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      constraints: const BoxConstraints.tightFor(
                        width: 52,
                        height: 52,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColores.ink900,
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

class _BotonContacto extends StatelessWidget {
  const _BotonContacto({
    required this.icono,
    required this.texto,
    required this.onTap,
    this.color,
    this.degradado,
  });

  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final Color? color;
  final Gradient? degradado;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: degradado,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono, color: Colors.white),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      texto,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
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
