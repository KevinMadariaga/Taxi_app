// Contadores diarios de solicitudes para el panel del admin.
//
// No se pueden calcular leyendo `solicitudes` después: las canceladas se
// borran a los 30 min (`purgarSolicitudesCanceladas`). Por eso cada evento
// suma en `estadisticas_diarias/{AAAA-MM-DD}` en el momento en que pasa.

// Colombia no tiene horario de verano: UTC-5 fijo.
const OFFSET_COLOMBIA_MS = -5 * 60 * 60 * 1000;

/** Día (`AAAA-MM-DD`) y hora (`HH`) en Colombia de [ms] (epoch). */
function diaYHoraColombia(ms) {
  const d = new Date(ms + OFFSET_COLOMBIA_MS);
  const dia = d.toISOString().slice(0, 10);
  const hora = String(d.getUTCHours()).padStart(2, "0");
  return { dia, hora };
}

/** Contador de un resultado final, o `null` si [estado] no es final. */
function contadorDeResultado(estado) {
  if (estado === "completado") return "completadas";
  if (estado === "cancelado") return "canceladas";
  if (estado === "sin respuesta") return "sinRespuesta";
  return null;
}

/**
 * Qué contador sumar cuando el estado pasa de [antes] a [despues] (ya
 * normalizados), o `null`. Solo la primera llegada a un estado final
 * cuenta: pasar de cancelado a sin respuesta (o al revés) no suma dos
 * veces la misma solicitud.
 */
function resultadoNuevo(antes, despues) {
  if (antes === despues) return null;
  if (contadorDeResultado(antes)) return null;
  return contadorDeResultado(despues);
}

module.exports = { diaYHoraColombia, contadorDeResultado, resultadoNuevo };
