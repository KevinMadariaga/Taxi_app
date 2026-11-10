// Correr: cd functions && node --test
//
// Módulo puro, sin emulador ni firebase-admin.

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  MAX_CLAVE_BYTES,
  CANALES,
  canalPara,
  claveNotificacion,
  idNotificacion,
  buildFcmMessage,
  buildRetiroMessage,
} = require("./notificaciones");

// ─────────────────────────────────────────────────────────────────────────────
// VECTORES DEL CONTRATO ENTRE LENGUAJES
//
// Estos mismos pares están fijados del lado Dart en
// `test/notificacion_clave_test.dart`. La app cancela una notificación por su
// id entero, y ese id lo calcula el backend: si el hash cambia de un solo
// lado, las notificaciones dejan de poder retirarse y NADA falla a la vista —
// se descubriría en producción, con la bandeja del conductor llena.
//
// Si hay que cambiar el algoritmo, se cambian los dos lados y estos vectores.
// ─────────────────────────────────────────────────────────────────────────────
const VECTORES = [
  ["nueva_solicitud_cli123", 1645069590],
  ["viaje_solABC", 448669161],
  ["chat_solABC", 1848650506],
  ["general", 616112491],
];

test("idNotificacion respeta los vectores del contrato con Dart", () => {
  for (const [clave, esperado] of VECTORES) {
    assert.equal(idNotificacion(clave), esperado, `clave: ${clave}`);
  }
});

test("idNotificacion es estable y cabe en un int32 con signo", () => {
  for (const clave of ["a", "nueva_solicitud_xyz", "x".repeat(64)]) {
    const id = idNotificacion(clave);
    assert.equal(id, idNotificacion(clave));
    assert.ok(Number.isInteger(id));
    assert.ok(id >= 0 && id <= 0x7fffffff, `fuera de rango: ${id}`);
  }
});

test("claves distintas dan ids distintos en los casos que usamos", () => {
  const claves = [
    claveNotificacion("nueva_solicitud", "cli1"),
    claveNotificacion("nueva_solicitud", "cli2"),
    claveNotificacion("trip_status_change", "sol1"),
    claveNotificacion("trip_chat_message", "sol1"),
    claveNotificacion("payment_method_change", "sol1"),
  ];
  assert.equal(new Set(claves.map(idNotificacion)).size, claves.length);
});

test("claveNotificacion arma <type>_<entidad> y sanea la entrada", () => {
  assert.equal(claveNotificacion("nueva_solicitud", "cli123"), "nueva_solicitud_cli123");
  assert.equal(claveNotificacion("chat", "sol/../otro"), "chat_solotro");
  assert.equal(claveNotificacion("tipo", "  con espacios  "), "tipo_conespacios");
});

test("claveNotificacion tolera entidad ausente", () => {
  assert.equal(claveNotificacion("emergencia"), "emergencia");
  assert.equal(claveNotificacion("emergencia", ""), "emergencia");
  assert.equal(claveNotificacion("emergencia", null), "emergencia");
  assert.equal(claveNotificacion(""), "general");
});

test("claveNotificacion corta a 64 bytes (límite de apns-collapse-id)", () => {
  const clave = claveNotificacion("trip_status_change", "x".repeat(200));
  assert.ok(Buffer.byteLength(clave, "utf8") <= MAX_CLAVE_BYTES);
});

test("buildFcmMessage aplica la MISMA clave en las tres plataformas", () => {
  const msg = buildFcmMessage({
    token: "tok",
    title: "T",
    body: "B",
    type: "trip_status_change",
    entidad: "solABC",
  });
  const clave = "trip_status_change_solABC";

  assert.equal(msg.android.collapseKey, clave);
  assert.equal(msg.android.notification.tag, clave);
  assert.equal(msg.apns.headers["apns-collapse-id"], clave);
  assert.equal(msg.data.notifClave, clave);
  assert.equal(msg.data.notifId, String(idNotificacion(clave)));
  assert.equal(msg.token, "tok");
  assert.equal(msg.tokens, undefined);
});

test("buildFcmMessage por defecto sigue mostrando la notificación", () => {
  const msg = buildFcmMessage({
    token: "tok",
    title: "T",
    body: "B",
    type: "trip_status_change",
    entidad: "s1",
  });
  assert.deepEqual(msg.notification, { title: "T", body: "B" });
  assert.deepEqual(msg.apns.payload.aps.alert, { title: "T", body: "B" });
  // Sin estado: aviso general de Ride; el canal legado queda en data.
  assert.equal(msg.android.notification.channelId, "avisos_v1");
  assert.equal(msg.data.channelId, "taxi_trip_channel");
});

test("soloData quita el notification de nivel superior pero deja visible iOS", () => {
  const msg = buildFcmMessage({
    tokens: ["a", "b"],
    title: "Solicitud entrante",
    body: "Un cliente cerca de ti necesita servicio",
    type: "nueva_solicitud",
    entidad: "cli123",
    soloData: true,
  });

  // Android: data-only → lo dibuja la app con notifId, y por eso se puede
  // cancelar después. Es toda la razón de ser de esta bandera.
  //
  // `android.notification` tiene que faltar TAMBIÉN: por sí solo ya convierte
  // el mensaje en notification message, el SO lo dibujaría sin título ni
  // cuerpo (que solo viajan en `data`) y el handler de la app saldría por
  // `message.notification != null` sin dibujar nada cancelable.
  assert.equal(msg.notification, undefined);
  assert.equal(msg.android.notification, undefined);
  assert.equal(msg.android.collapseKey, "nueva_solicitud_cli123");
  assert.equal(msg.data.channelId, "taxi_trip_channel");
  // iOS: el texto sigue viajando, así que la alerta se ve igual.
  assert.deepEqual(msg.apns.payload.aps.alert, {
    title: "Solicitud entrante",
    body: "Un cliente cerca de ti necesita servicio",
  });
  assert.equal(msg.data.title, "Solicitud entrante");
  assert.equal(msg.data.notifClave, "nueva_solicitud_cli123");
  assert.deepEqual(msg.tokens, ["a", "b"]);
  assert.equal(msg.token, undefined);
});

test("la clave de la solicitud entrante es el cliente, no la solicitud", () => {
  // Dos solicitudes distintas del MISMO cliente tienen que compartir id, que
  // es lo que hace que la segunda reemplace a la primera en la bandeja.
  const primera = buildFcmMessage({
    tokens: ["t"],
    title: "T",
    body: "B",
    type: "nueva_solicitud",
    entidad: "cliX",
    extraData: { solicitudId: "sol1" },
    soloData: true,
  });
  const segunda = buildFcmMessage({
    tokens: ["t"],
    title: "T",
    body: "B",
    type: "nueva_solicitud",
    entidad: "cliX",
    extraData: { solicitudId: "sol2" },
    soloData: true,
  });
  assert.equal(primera.data.notifId, segunda.data.notifId);
  assert.equal(primera.android.collapseKey, segunda.android.collapseKey);
  assert.equal(primera.data.notifClave, segunda.data.notifClave);

  // Y de otro cliente, NO.
  const otro = buildFcmMessage({
    tokens: ["t"],
    title: "T",
    body: "B",
    type: "nueva_solicitud",
    entidad: "cliY",
    soloData: true,
  });
  assert.notEqual(primera.data.notifId, otro.data.notifId);
});

test("buildFcmMessage permite sobrescribir el canal", () => {
  const msg = buildFcmMessage({
    tokens: ["t"],
    title: "T",
    body: "B",
    type: "emergencia",
    entidad: "e1",
    channelId: "taxi_emergencia_channel",
  });
  assert.equal(msg.android.notification.channelId, "taxi_emergencia_channel");
});

test("buildRetiroMessage es silencioso y apunta a la misma clave", () => {
  const clave = claveNotificacion("nueva_solicitud", "cli123");
  const msg = buildRetiroMessage({
    tokens: ["a"],
    clave,
    extraData: { solicitudId: "sol1" },
  });

  assert.equal(msg.data.type, "retirar_notificacion");
  assert.equal(msg.data.notifId, String(idNotificacion(clave)));
  assert.equal(msg.data.solicitudId, "sol1");
  // Nada que mostrar: ni notification ni alert.
  assert.equal(msg.notification, undefined);
  assert.equal(msg.apns.payload.aps.alert, undefined);
  assert.equal(msg.apns.payload.aps["content-available"], 1);
  assert.equal(msg.apns.headers["apns-push-type"], "background");
  assert.equal(msg.apns.headers["apns-priority"], "5");
  assert.equal(msg.android.priority, "high");
});

// ─── Canales con sonido propio (contrato con canales_notificacion.dart) ───

test("canalPara elige el canal de cada evento", () => {
  assert.equal(canalPara("nueva_solicitud"), CANALES.solicitudes);
  assert.equal(canalPara("conductor_cerca"), CANALES.estadoViaje);
  assert.equal(canalPara("contraoferta"), CANALES.estadoViaje);
  for (const e of ["buscando", "asignado", "en espera", "en camino", "en ruta", "completado"]) {
    assert.equal(canalPara("trip_status_change", e), CANALES.estadoViaje, e);
  }
  for (const e of ["cancelado", "sin respuesta"]) {
    assert.equal(canalPara("trip_status_change", e), CANALES.cancelado, e);
  }
  for (const t of ["trip_chat_message", "soporte_chat", "soporte_chat_respuesta"]) {
    assert.equal(canalPara(t), CANALES.mensajes, t);
  }
  assert.equal(canalPara("promo"), CANALES.promociones);
  for (const t of ["membresia_activada", "payment_method_change", "reporte", "sugerencia",
    "solicitud_conductor", "nuevo_cliente"]) {
    assert.equal(canalPara(t), CANALES.avisos, t);
  }
  assert.equal(canalPara("emergencia"), null);
});

test("la nueva solicitud suena con su sonido en Android e iOS", () => {
  const msg = buildFcmMessage({
    tokens: ["t"],
    title: "T",
    body: "B",
    type: "nueva_solicitud",
    entidad: "cli1",
    soloData: true,
    extraData: { solicitudId: "s1" },
  });
  // Data-only: la dibuja la app, con el canal de `data.canal`.
  assert.equal(msg.data.canal, "solicitudes_conductor_v1");
  // Las versiones viejas siguen viendo el canal de siempre.
  assert.equal(msg.data.channelId, "taxi_trip_channel");
  assert.equal(msg.android.notification, undefined);
  assert.equal(msg.apns.payload.aps.sound, "nueva_solicitud.caf");
  assert.equal(msg.apns.payload.aps["interruption-level"], "time-sensitive");
});

test("el cambio de estado al pasajero usa el sonido de estado", () => {
  const msg = buildFcmMessage({
    token: "t",
    title: "T",
    body: "B",
    type: "trip_status_change",
    entidad: "s1",
    extraData: { solicitudId: "s1", estado: "asignado" },
  });
  assert.equal(msg.android.notification.channelId, "estado_viaje_v1");
  assert.equal(msg.android.notification.sound, "estado_viaje");
  assert.equal(msg.apns.payload.aps.sound, "estado_viaje.caf");
  assert.equal(msg.apns.payload.aps["interruption-level"], undefined);
});

test("la emergencia conserva su canal y la alarma del sistema", () => {
  const msg = buildFcmMessage({
    token: "t", title: "T", body: "B", type: "emergencia", entidad: "e1",
    channelId: "taxi_emergencia_channel",
  });
  assert.equal(msg.android.notification.channelId, "taxi_emergencia_channel");
  assert.equal(msg.android.notification.sound, "default");
  assert.equal(msg.apns.payload.aps.sound, "default");
  assert.equal(msg.data.canal, undefined);
});

test("todo lo demás suena a Ride", () => {
  const msg = buildFcmMessage({ token: "t", title: "T", body: "B", type: "payment_method_change", entidad: "s1" });
  assert.equal(msg.android.notification.channelId, "avisos_v1");
  assert.equal(msg.apns.payload.aps.sound, "mensaje.caf");
});

test("cancelado y mensajes suenan con su sonido", () => {
  const cancel = buildFcmMessage({
    token: "t", title: "T", body: "B", type: "trip_status_change", entidad: "s1",
    extraData: { estado: "cancelado" },
  });
  assert.equal(cancel.android.notification.channelId, "viaje_cancelado_v1");
  assert.equal(cancel.apns.payload.aps.sound, "viaje_cancelado.caf");
  const chat = buildFcmMessage({ token: "t", title: "T", body: "B", type: "trip_chat_message", entidad: "s1" });
  assert.equal(chat.android.notification.channelId, "mensajes_v1");
  assert.equal(chat.apns.payload.aps.sound, "mensaje.caf");
});
