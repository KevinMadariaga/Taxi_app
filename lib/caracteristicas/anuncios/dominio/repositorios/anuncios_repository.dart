import 'dart:typed_data';

import '../entidades/anuncio.dart';
import '../entidades/promocion.dart';

abstract class AnunciosRepository {
  /// Todos los anuncios, más nuevo primero (el admin ve también los
  /// vencidos para borrarlos).
  Stream<List<Anuncio>> watchAnuncios();

  /// Optimiza y sube la imagen (ya recortada) y crea el anuncio. [dias] nulo: sin
  /// vencimiento.
  Future<void> crearAnuncio(
    Uint8List imagen, {
    int? dias,
    String titulo = '',
    String detalle = '',
    String whatsapp = '',
    String instagram = '',
  });

  /// Cambia los datos del anuncio. [nuevaImagen] reemplaza la actual;
  /// [dias]: `null` deja el vencimiento como estaba, `0` lo quita.
  Future<void> actualizarAnuncio(
    Anuncio anuncio, {
    required String titulo,
    required String detalle,
    required String whatsapp,
    required String instagram,
    int? dias,
    Uint8List? nuevaImagen,
  });

  Future<void> eliminarAnuncio(Anuncio anuncio);

  /// Las promociones enviadas, más nueva primero: el historial del admin
  /// (50) o las recientes que puede mostrar el inicio (pocas).
  Stream<List<Promocion>> watchPromociones({int limite = 50});

  /// La promoción [id] (la que traía la notificación tocada), o `null` si
  /// ya no existe.
  Future<Promocion?> obtenerPromocion(String id);

  /// Sube la imagen (si hay) y manda la promoción por la Cloud Function.
  /// Corrige una promoción ya enviada (no vuelve a mandar la notificación).
  /// [nuevaImagen] reemplaza la actual; [quitarImagen] la saca; [dias]
  /// nulo deja la vigencia como estaba.
  Future<void> actualizarPromocion(
    Promocion promo, {
    required String titulo,
    required String cuerpo,
    required AudienciaPromocion audiencia,
    int? dias,
    Uint8List? nuevaImagen,
    bool quitarImagen = false,
  });

  Future<void> eliminarPromocion(Promocion promo);

  /// Ids de las promociones que ya se mostraron en este teléfono.
  Future<Set<String>> promocionesVistas();

  Future<void> marcarPromocionVista(String id);

  Future<void> enviarPromocion({
    required String titulo,
    required String cuerpo,
    required AudienciaPromocion audiencia,
    required int diasVigencia,
    Uint8List? imagen,
  });
}
