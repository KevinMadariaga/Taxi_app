// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  MAX_CANCELACIONES,
  VENTANA_MS,
  PAUSA_MS,
  canceladoPorConductor,
  registrarCancelacion,
} = require("./sanciones");

const T = 1_800_000_000_000;

test("canceladoPorConductor solo con cancelledBy = conductor", () => {
  assert.equal(canceladoPorConductor({ cancelledBy: "conductor" }), true);
  assert.equal(canceladoPorConductor({ cancelledBy: "Conductor " }), true);
  assert.equal(canceladoPorConductor({ cancelledBy: "cliente" }), false);
  assert.equal(canceladoPorConductor({ cancelReason: "inactividad_timeout" }), false);
  assert.equal(canceladoPorConductor(null), false);
});

test("las primeras 5 cancelaciones solo se cuentan", () => {
  let previas = [];
  for (let i = 0; i < MAX_CANCELACIONES; i++) {
    const r = registrarCancelacion(previas, T + i);
    assert.equal(r.bloqueadoHasta, null);
    previas = r.cancelaciones;
  }
  assert.equal(previas.length, 5);
});

test("la 6ª dentro de 24 h bloquea 15 min y reinicia el conteo", () => {
  const previas = [T, T + 1, T + 2, T + 3, T + 4];
  const r = registrarCancelacion(previas, T + 10);
  assert.equal(r.bloqueadoHasta, T + 10 + PAUSA_MS);
  assert.deepEqual(r.cancelaciones, []);
});

test("las de hace más de 24 h no cuentan", () => {
  const viejas = [T, T + 1, T + 2, T + 3, T + 4];
  const ahora = T + VENTANA_MS + 5;
  const r = registrarCancelacion(viejas, ahora);
  assert.equal(r.bloqueadoHasta, null);
  assert.deepEqual(r.cancelaciones, [ahora]);
});

test("datos basura en el doc no rompen el conteo", () => {
  const r = registrarCancelacion([null, "x", T], T + 1);
  assert.deepEqual(r.cancelaciones, [T, T + 1]);
  assert.deepEqual(registrarCancelacion(undefined, T).cancelaciones, [T]);
});
