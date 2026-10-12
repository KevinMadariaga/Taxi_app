// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { diaYHoraColombia, resultadoNuevo } = require("./estadisticas");

test("una solicitud a las 11 pm de Colombia cuenta en ese día, no en el siguiente UTC", () => {
  // 2026-10-12 23:30 en Colombia = 2026-10-13 04:30 UTC.
  const ms = Date.UTC(2026, 9, 13, 4, 30);
  assert.deepEqual(diaYHoraColombia(ms), { dia: "2026-10-12", hora: "23" });
});

test("medianoche de Colombia abre el día nuevo", () => {
  const ms = Date.UTC(2026, 9, 13, 5, 0);
  assert.deepEqual(diaYHoraColombia(ms), { dia: "2026-10-13", hora: "00" });
});

test("llegar a completado o cancelado suma su contador", () => {
  assert.equal(resultadoNuevo("en ruta", "completado"), "completadas");
  assert.equal(resultadoNuevo("buscando", "cancelado"), "canceladas");
  assert.equal(resultadoNuevo("buscando", "sin respuesta"), "sinRespuesta");
});

test("cambios entre estados no finales, o entre finales, no suman", () => {
  assert.equal(resultadoNuevo("buscando", "asignado"), null);
  assert.equal(resultadoNuevo("cancelado", "sin respuesta"), null);
  assert.equal(resultadoNuevo("completado", "completado"), null);
});
