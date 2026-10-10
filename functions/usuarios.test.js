// Correr: cd functions && node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { esRegistroDeClienteCompletado } = require("./usuarios");

const completo = { rol: "cliente", isProfileComplete: true, foto: "https://f" };

test("al completar el registro con foto: avisa", () => {
  assert.equal(
    esRegistroDeClienteCompletado(
      { rol: "cliente", isProfileComplete: false },
      completo,
    ),
    true,
  );
});

test("el doc nació solo con el token FCM: avisa al completar", () => {
  assert.equal(
    esRegistroDeClienteCompletado({ fcmToken: "t" }, { fcmToken: "t", ...completo }),
    true,
  );
});

test("cuenta creada pero sin terminar (sin foto): NO avisa", () => {
  assert.equal(
    esRegistroDeClienteCompletado(null, {
      rol: "cliente",
      isProfileComplete: false,
      nombre: "Ana",
    }),
    false,
  );
  assert.equal(
    esRegistroDeClienteCompletado(null, {
      rol: "cliente",
      isProfileComplete: true,
      foto: "",
    }),
    false,
  );
});

test("cliente que ya estaba completo y edita su perfil: NO avisa", () => {
  assert.equal(
    esRegistroDeClienteCompletado(completo, { ...completo, nombre: "Ana" }),
    false,
  );
});

test("conductor que vuelve a ser cliente: NO avisa", () => {
  assert.equal(
    esRegistroDeClienteCompletado({ ...completo, rol: "conductor" }, completo),
    false,
  );
});
