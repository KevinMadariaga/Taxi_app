/// Calificación del conductor tal como se le muestra (inicio y perfil deben
/// coincidir, por eso una sola función).
///
/// Prioriza el promedio consolidado que la Cloud Function escribe en
/// `usuarios/{uid}` (`calificacionConductor`/`calificacionPromedio` +
/// `totalCalificaciones`). Si ese doc no tiene calificaciones (conductores
/// calificados antes de la función), promedia la `calificacion` de sus
/// viajes completados. Sin nada: `total == 0`.
({double promedio, int total}) resolverCalificacionConductor(
  Map<String, dynamic>? perfil,
  Iterable<Map<String, dynamic>> viajesCompletados,
) {
  final p = perfil ?? const <String, dynamic>{};
  final totalDoc =
      _entero(
        p['totalCalificaciones'] ?? p['ratingCount'] ?? p['totalRatings'],
      ) ??
      0;
  final promedioDoc = _decimal(
    p['calificacionConductor'] ??
        p['calificacionPromedio'] ??
        p['ratingPromedio'] ??
        p['rating'],
  );
  if (totalDoc > 0 && promedioDoc != null) {
    return (promedio: promedioDoc.clamp(0.0, 5.0).toDouble(), total: totalDoc);
  }

  var suma = 0.0;
  var n = 0;
  for (final v in viajesCompletados) {
    final puntaje = puntajeViaje(v);
    if (puntaje == null) continue;
    suma += puntaje;
    n++;
  }
  return n > 0 ? (promedio: suma / n, total: n) : (promedio: 0.0, total: 0);
}

/// Puntaje que el pasajero le dio al conductor en un viaje.
double? puntajeViaje(Map<String, dynamic> viaje) {
  final raw = viaje['calificacion'] ?? viaje['calificacion_cliente'];
  if (raw is Map) {
    return _decimal(raw['score'] ?? raw['puntaje'] ?? raw['valor']);
  }
  return _decimal(raw);
}

double? _decimal(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

int? _entero(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
