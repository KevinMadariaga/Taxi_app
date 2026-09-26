// Reglas puras de las calificaciones (sin firebase-admin), para poder
// probarlas con `node --test`. `onCalificacionRegistrada` (index.js) solo
// decide con esto y escribe dentro de una transacción.

/**
 * Puntaje nuevo del campo [campo] si recién apareció en este update (antes
 * no estaba, ahora sí y es un número 1–5); si no, null. Solo se acumula la
 * primera vez: cualquier escritura posterior al doc con la calificación ya
 * puesta no debe sumarla de nuevo.
 */
function calificacionNueva(before, after, campo) {
  if (!before || !after) return null;
  if (before[campo] != null || after[campo] == null) return null;
  const puntaje = Number(after[campo]);
  if (!Number.isFinite(puntaje) || puntaje < 1 || puntaje > 5) return null;
  return puntaje;
}

/** Promedio acumulado tras sumar [nuevo] a [total] calificaciones previas. */
function acumular(promedio, total, nuevo) {
  const t = Number.isFinite(total) && total > 0 ? total : 0;
  const p = Number.isFinite(promedio) ? promedio : 0;
  const nuevoTotal = t + 1;
  return { promedio: (p * t + nuevo) / nuevoTotal, total: nuevoTotal };
}

module.exports = { calificacionNueva, acumular };
