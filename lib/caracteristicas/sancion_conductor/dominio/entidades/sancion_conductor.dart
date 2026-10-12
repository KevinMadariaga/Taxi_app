/// Estado de `sanciones_conductores/{uid}`: lo escribe solo la Cloud Function
/// `onSolicitudEstadoChangeConductor` (ver `functions/sanciones.js`, que es
/// quien DECIDE la pausa). Acá se usa para avisar antes de cancelar y para la
/// cuenta regresiva del modal.
class SancionConductor {
  const SancionConductor({this.cancelaciones = const [], this.bloqueadoHasta});

  static const SancionConductor ninguna = SancionConductor();

  /// Mismos números que `functions/sanciones.js` — mantenerlos alineados.
  static const int maxCancelaciones = 5;
  static const Duration ventana = Duration(hours: 24);
  // Debe coincidir con `PAUSA_MS` de functions/sanciones.js.
  static const Duration pausa = Duration(minutes: 15);

  final List<DateTime> cancelaciones;
  final DateTime? bloqueadoHasta;

  /// Lo que falta de pausa; [Duration.zero] si no hay o ya venció.
  Duration restante(DateTime ahora) {
    final hasta = bloqueadoHasta;
    if (hasta == null || !hasta.isAfter(ahora)) return Duration.zero;
    return hasta.difference(ahora);
  }

  int cancelacionesEnVentana(DateTime ahora) =>
      cancelaciones.where((t) => ahora.difference(t) < ventana).length;

  /// Aviso para el diálogo de confirmación cuando está cerca del límite;
  /// `null` si todavía le sobran.
  String? avisoAntesDeCancelar(DateTime ahora) {
    final n = cancelacionesEnVentana(ahora);
    if (n >= maxCancelaciones) {
      return 'Llevas $n cancelaciones hoy: si cancelas este viaje tendrás una '
          'pausa de ${pausa.inMinutes} min sin recibir solicitudes.';
    }
    if (n == maxCancelaciones - 1) {
      return 'Llevas $n cancelaciones hoy. Al pasar de $maxCancelaciones '
          'tendrás una pausa de ${pausa.inMinutes} min sin recibir solicitudes.';
    }
    return null;
  }
}
