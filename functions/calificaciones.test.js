// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { calificacionNueva, acumular } = require("./calificaciones");

test("calificacionNueva: solo la primera vez que aparece", () => {
  const campo = "calificacionCliente";
  assert.equal(calificacionNueva({}, { [campo]: 4 }, campo), 4);
  // Ya estaba: otra escritura al doc no la vuelve a contar.
  assert.equal(calificacionNueva({ [campo]: 4 }, { [campo]: 4 }, campo), null);
  // Todavía no hay calificación.
  assert.equal(calificacionNueva({}, { estado: "completado" }, campo), null);
});

test("calificacionNueva: descarta puntajes inválidos", () => {
  const campo = "calificacionCliente";
  for (const malo of [0, 6, "abc", NaN]) {
    assert.equal(calificacionNueva({}, { [campo]: malo }, campo), null);
  }
  assert.equal(calificacionNueva(null, { [campo]: 4 }, campo), null);
});

test("acumular: promedio ponderado por el total previo", () => {
  assert.deepEqual(acumular(0, 0, 5), { promedio: 5, total: 1 });
  assert.deepEqual(acumular(4, 3, 2), { promedio: 3.5, total: 4 });
  // Datos previos ausentes o corruptos cuentan como vacío.
  assert.deepEqual(acumular(undefined, NaN, 3), { promedio: 3, total: 1 });
});
