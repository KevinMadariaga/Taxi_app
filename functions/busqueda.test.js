// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { debeRepartirDeNuevo, motivoDeVencimiento } = require("./busqueda");

const carro = { tipoVehiculo: "carro" };
const moto = { tipoVehiculo: "moto" };
const MIN = 60 * 1000;

test("un viaje programado que se activa reparte a los conductores", () => {
  assert.equal(debeRepartirDeNuevo("programada", "buscando", carro, carro), true);
});

test("cambiar de carro a moto buscando avisa a los conductores de moto", () => {
  assert.equal(debeRepartirDeNuevo("buscando", "buscando", carro, moto), true);
});

test("cualquier otra escritura de una búsqueda no reparte de nuevo", () => {
  assert.equal(debeRepartirDeNuevo("buscando", "buscando", carro, carro), false);
  assert.equal(debeRepartirDeNuevo("buscando", "asignado", carro, carro), false);
  assert.equal(debeRepartirDeNuevo("programada", "cancelado", carro, carro), false);
});

test("sin aviso vence a los 15 min", () => {
  assert.equal(motivoDeVencimiento({}, 0, 14 * MIN), null);
  assert.equal(motivoDeVencimiento({}, 0, 15 * MIN), "inactividad_timeout");
});

test("con 'Avísame' sigue buscando hasta los 30 min y avisa que no hubo", () => {
  const data = { avisarAlEncontrar: true };
  assert.equal(motivoDeVencimiento(data, 0, 29 * MIN), null);
  assert.equal(motivoDeVencimiento(data, 0, 30 * MIN), "sin_conductor");
});
