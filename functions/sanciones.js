// Pausa por cancelaciones del conductor.
//
// Regla de negocio: si el conductor cancela MÁS de 5 viajes dentro de 24 h,
// queda 15 min sin recibir ni aceptar solicitudes, y su conteo vuelve a cero.
// El estado vive en `sanciones_conductores/{uid}` (`cancelaciones`: lista de
// instantes en ms dentro de la ventana; `bloqueadoHasta`: Timestamp), que
// solo escribe el servidor — si lo escribiera la app, el conductor podría
// borrarse la pausa.
//
// Los mismos tres números están en Dart (`SancionConductor`): la app los usa
// solo para avisar y para la cuenta regresiva; quien decide es este módulo.
//
// Módulo puro (sin firebase-admin) para testearlo con `node --test`.

const MAX_CANCELACIONES = 5;
const VENTANA_MS = 24 * 60 * 60 * 1000;
// Debe coincidir con `SancionConductor.pausa` en Dart (cuenta regresiva).
const PAUSA_MS = 15 * 60 * 1000;

/** La app marca quién canceló en `cancelledBy` ('cliente' | 'conductor');
 * las cancelaciones automáticas del servidor no lo llevan. */
function canceladoPorConductor(data) {
  return String((data && data.cancelledBy) || "").toLowerCase().trim() === "conductor";
}

/**
 * Suma una cancelación a [previas] (ms) en el instante [ahora] (ms).
 * Devuelve `{cancelaciones, bloqueadoHasta}`; `bloqueadoHasta` es `null`
 * cuando esta cancelación no dispara pausa (no hay que tocar la vigente).
 */
function registrarCancelacion(previas, ahora) {
  const vigentes = (Array.isArray(previas) ? previas : []).filter(
    (t) => typeof t === "number" && ahora - t < VENTANA_MS && t <= ahora
  );
  vigentes.push(ahora);
  if (vigentes.length > MAX_CANCELACIONES) {
    return { cancelaciones: [], bloqueadoHasta: ahora + PAUSA_MS };
  }
  return { cancelaciones: vigentes, bloqueadoHasta: null };
}

module.exports = {
  MAX_CANCELACIONES,
  VENTANA_MS,
  PAUSA_MS,
  canceladoPorConductor,
  registrarCancelacion,
};
