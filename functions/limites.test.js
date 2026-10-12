// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { unaVez, evaluarCupo } = require("./limites");

/** Firestore mínimo en memoria: solo lo que usa `unaVez`. */
function dbFalsa() {
  const docs = new Map();
  return {
    docs,
    collection: (c) => ({
      doc: (id) => ({
        create: async (data) => {
          const k = `${c}/${id}`;
          if (docs.has(k)) {
            const e = new Error("6 ALREADY_EXISTS: Document already exists");
            e.code = 6;
            throw e;
          }
          docs.set(k, data);
        },
      }),
    }),
  };
}

test("el mismo evento en el mismo trigger se procesa una sola vez", async () => {
  const db = dbFalsa();
  const ev = { id: "evt-1" };
  assert.equal(await unaVez(ev, "onTripChatMessageCreated", { db }), true);
  assert.equal(await unaVez(ev, "onTripChatMessageCreated", { db }), false);
});

test("el mismo evento en otro trigger sí se procesa", async () => {
  const db = dbFalsa();
  const ev = { id: "evt-1" };
  assert.equal(await unaVez(ev, "onSolicitudEstadoChange", { db }), true);
  assert.equal(await unaVez(ev, "estadisticasSolicitudEstado", { db }), true);
});

test("sin id de evento no bloquea el aviso", async () => {
  assert.equal(await unaVez({}, "x", { db: dbFalsa() }), true);
});

test("cupo: 5 por hora, la sexta se rechaza y dice cuándo reintentar", () => {
  const opciones = { max: 5, ventanaMs: 3600000 };
  let estado = null;
  for (let i = 0; i < 5; i++) {
    const r = evaluarCupo(estado, { ...opciones, ahora: 1000 + i });
    assert.equal(r.permitido, true);
    estado = r.nuevo;
  }
  const sexta = evaluarCupo(estado, { ...opciones, ahora: 2000 });
  assert.equal(sexta.permitido, false);
  assert.equal(sexta.reintentarEnMs, 1000 + 3600000 - 2000);
});

test("cupo: pasada la ventana vuelve a empezar", () => {
  const r = evaluarCupo(
    { inicio: 0, usados: 5 },
    { max: 5, ventanaMs: 3600000, ahora: 3600000 },
  );
  assert.equal(r.permitido, true);
  assert.deepEqual(r.nuevo, { inicio: 3600000, usados: 1 });
});

test("si Firestore falla al marcar, el aviso sale igual", async () => {
  const db = {
    collection: () => ({
      doc: () => ({
        create: async () => {
          const e = new Error("14 UNAVAILABLE");
          e.code = 14;
          throw e;
        },
      }),
    }),
  };
  assert.equal(await unaVez({ id: "e" }, "x", { db }), true);
});
