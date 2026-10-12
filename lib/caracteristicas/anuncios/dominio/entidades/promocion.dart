import 'package:flutter/foundation.dart';

/// Público de una promoción. El `name` es lo que se guarda en Firestore y
/// lo que valida `enviarPromocion` (functions/index.js).
enum AudienciaPromocion { clientes, conductores, todos }

/// Promoción del admin: llega por notificación y, al tocarla, se abre como
/// ventana en el inicio.
@immutable
class Promocion {
  const Promocion({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.imagenUrl,
    required this.audiencia,
    required this.venceEn,
    this.creadoEn,
  });

  final String id;
  final String titulo;
  final String cuerpo;
  final String imagenUrl;
  final AudienciaPromocion audiencia;
  final DateTime? venceEn;

  /// Cuándo se envió (nulo un instante, hasta que llega la hora del servidor).
  final DateTime? creadoEn;

  bool esPara(AudienciaPromocion publico) =>
      audiencia == AudienciaPromocion.todos || audiencia == publico;

  bool vigente(DateTime ahora) => venceEn == null || venceEn!.isAfter(ahora);
}

/// La que sale sola en el inicio: la más reciente de [recientes] (más nueva
/// primero) que sea para [publico], siga vigente y no se haya visto.
Promocion? promocionParaMostrar(
  List<Promocion> recientes, {
  required AudienciaPromocion publico,
  required Set<String> vistas,
  required DateTime ahora,
}) {
  for (final p in recientes) {
    if (p.esPara(publico) && p.vigente(ahora) && !vistas.contains(p.id)) {
      return p;
    }
  }
  return null;
}
