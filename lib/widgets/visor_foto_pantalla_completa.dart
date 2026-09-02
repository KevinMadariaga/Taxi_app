import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Abre una foto como modal centrada en la pantalla (no a pantalla
/// completa), con zoom (pellizcar/doble tap) para verla más de cerca. Usado
/// para las fotos de conductor/vehículo en la tarjeta de viaje del cliente.
Future<void> mostrarFotoPantallaCompleta(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _VisorFotoModal(url: url),
  );
}

class _VisorFotoModal extends StatelessWidget {
  const _VisorFotoModal({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.topRight,
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: size.width * 0.85,
                maxHeight: size.height * 0.6,
              ),
              color: Colors.black,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, _, error) => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -12,
            right: -12,
            child: Material(
              color: Colors.black,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
