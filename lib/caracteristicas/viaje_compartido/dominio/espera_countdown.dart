/// Cálculo puro del remanente del temporizador de espera (estado
/// `en espera`, ~3 min para que el cliente confirme "voy en camino").
///
/// Sin esta función, cliente y conductor calculaban el remanente contra el
/// momento en que CADA dispositivo veía `en espera` por primera vez — dos
/// relojes independientes, sin ancla compartida. Ahora ambos parten del
/// mismo `esperaIniciadaEn` (`FieldValue.serverTimestamp()`, escrito una
/// sola vez por `SolicitudFirestoreDatasource.actualizarEstado`).
///
/// `inicio == null` cubre dos casos reales: el viaje nunca pasó por
/// `en espera` todavía (la escritura del estado y la del ancla no son
/// atómicas, así que puede llegar un snapshot intermedio), o es un viaje
/// viejo creado antes de que este campo existiera. En ambos, se conserva el
/// comportamiento previo: arrancar en `total`.
int segundosRestantesEspera({
  required DateTime? inicio,
  required DateTime ahora,
  int total = 180,
}) {
  if (inicio == null) return total;

  final transcurrido = ahora.difference(inicio).inSeconds;
  // `transcurrido` negativo (deriva de reloj local vs. serverTimestamp, o el
  // snapshot llegó con el estimate optimista de escritura local antes de
  // confirmarse) no debe dar más de `total` — se acota igual que el resto.
  return (total - transcurrido).clamp(0, total);
}
