import 'package:flutter/foundation.dart';

/// Proporción de la imagen de un anuncio (ancho / alto): la de la tarjeta
/// del carrusel en un teléfono. El recorte, la vista previa y el detalle
/// usan la misma.
const double kProporcionAnuncio = 3 / 2;

/// Anuncio de un negocio en el carrusel del inicio del cliente.
@immutable
class Anuncio {
  const Anuncio({
    required this.id,
    required this.imagenUrl,
    required this.creadoEn,
    this.venceEn,
    this.titulo = '',
    this.detalle = '',
    this.whatsapp = '',
    this.instagram = '',
  });

  final String id;
  final String imagenUrl;
  final DateTime creadoEn;

  /// Sin valor: se muestra hasta que el admin lo borre.
  final DateTime? venceEn;

  final String titulo;
  final String detalle;

  /// Número del negocio (como lo escribió el admin).
  final String whatsapp;

  /// Usuario (`@negocio`) o enlace de Instagram.
  final String instagram;

  bool vigente(DateTime ahora) => venceEn == null || venceEn!.isAfter(ahora);

  /// Si tocarlo abre la ventana de detalle (hay algo más que la imagen).
  bool get tieneDetalle =>
      titulo.isNotEmpty ||
      detalle.isNotEmpty ||
      whatsapp.isNotEmpty ||
      instagram.isNotEmpty;
}
