/**
 * Claves e ids de deduplicación de notificaciones, y la plantilla de mensaje
 * FCM que las aplica.
 *
 * El problema que resuelve: antes ningún envío llevaba `collapseKey`, `tag` ni
 * `apns-collapse-id`, así que cada push creaba una entrada nueva en la bandeja
 * y ninguna podía reemplazar ni cancelar a otra. Un cliente que cancelaba y
 * volvía a pedir tres veces le dejaba al conductor tres "Solicitud entrante"
 * apiladas, y ninguna se iba cuando la solicitud moría.
 *
 * La idea es una sola: cada notificación tiene una CLAVE de deduplicación, y
 * de esa clave salen las dos cosas que hacen falta —
 *   - el `tag` / `collapseKey` / `apns-collapse-id` que usa el sistema
 *     operativo para REEMPLAZAR la anterior, y
 *   - el id entero que usa `flutter_local_notifications` en la app para poder
 *     CANCELARLA (`NotificacionesServicio.cancel`).
 *
 * El id se calcula acá y viaja en `data.notifId` en vez de que la app lo
 * derive por su cuenta: `String.hashCode` de Dart no está garantizado estable
 * entre versiones del SDK, y el handler de background corre en un isolate
 * aparte. Que las dos puntas coincidan es lo que hace cancelable la
 * notificación, así que el valor lo fija un solo lado.
 *
 * Módulo puro a propósito (sin `firebase-admin`): así se testea con
 * `node --test` sin emulador. Ver `notificaciones.test.js`.
 */

/** Límite de `apns-collapse-id` según la documentación de APNs. */
const MAX_CLAVE_BYTES = 64;

/**
 * Clave de deduplicación de una notificación: `<type>_<entidad>`.
 *
 * La ENTIDAD es lo que decide qué reemplaza a qué. Para la solicitud entrante
 * es el `clienteId` y no el `solicitudId` — es justamente lo que hace que el
 * mismo cliente pidiendo cuatro veces ocupe una sola entrada en la bandeja.
 * Para los avisos de un viaje es el `solicitudId`, para los de soporte el
 * `userId`.
 *
 * @param {string} type Tipo de notificación (`data.type`).
 * @param {string} [entidad] Identificador de a qué se refiere.
 * @returns {string} Clave saneada de a lo sumo 64 bytes.
 */
function claveNotificacion(type, entidad) {
  const limpia = (v) =>
    String(v ?? "")
      .trim()
      .replace(/[^A-Za-z0-9_-]/g, "");
  const base = limpia(type) || "general";
  const suf = limpia(entidad);
  const clave = suf ? `${base}_${suf}` : base;
  // INVARIANTE: el saneado de arriba deja la clave en ASCII puro, y de eso
  // depende que el hash coincida con el de Dart (allá se recorren code units
  // UTF-16, acá bytes UTF-8 — solo son lo mismo mientras sea ASCII). Cortar
  // por bytes es entonces redundante, pero deja el límite explícito. No
  // aflojar el regex sin cambiar las dos implementaciones.
  return Buffer.from(clave, "utf8").subarray(0, MAX_CLAVE_BYTES).toString("utf8");
}

/**
 * Id entero y estable para [clave], en `0..2^31-1`.
 *
 * FNV-1a de 32 bits: chico, sin dependencias y determinístico entre corridas —
 * que es todo lo que se necesita. No es criptográfico: una colisión solo
 * significaría que dos notificaciones distintas se pisan en la bandeja, no un
 * problema de seguridad.
 *
 * @param {string} clave
 * @returns {number}
 */
function idNotificacion(clave) {
  let hash = 0x811c9dc5;
  const bytes = Buffer.from(String(clave), "utf8");
  for (const b of bytes) {
    hash ^= b;
    // hash * 16777619 con aritmética de 32 bits sin desbordar el double.
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  // A positivo: `flutter_local_notifications` usa int de 32 bits con signo.
  return hash & 0x7fffffff;
}

/**
 * Arma el mensaje FCM con la deduplicación ya aplicada.
 *
 * @param {object} opts
 * @param {string} [opts.token] Destinatario único.
 * @param {string[]} [opts.tokens] Destinatarios (multicast).
 * @param {string} opts.title
 * @param {string} opts.body
 * @param {string} opts.type Va en `data.type` y es la base de la clave.
 * @param {string} [opts.entidad] Ver [claveNotificacion].
 * @param {object} [opts.extraData] Campos extra para `data`.
 * @param {boolean} [opts.soloData] Si es `true`, omite TANTO el `notification{}`
 *   de nivel superior COMO `android.notification`. Las dos cosas: en FCM v1
 *   `android.notification` por sí solo ya convierte el mensaje en notification
 *   message, y el SO lo dibujaría sin título ni cuerpo (que solo viajan en
 *   `data`) mientras el handler de la app sale por `message.notification !=
 *   null` — lo peor de los dos mundos. Sin ninguno de los dos, Android recibe
 *   data-only y la dibuja la app con `notifId`, que es lo único que la hace
 *   cancelable después; iOS la sigue mostrando porque el texto viaja en
 *   `apns.payload.aps.alert`.
 *
 *   OJO: Android NO entrega data-only si el usuario forzó el cierre de la app.
 *   Quien lo use tiene que tener una red de seguridad del lado de la app.
 * @param {string} [opts.channelId] Canal Android (default `taxi_trip_channel`).
 * @returns {object} Mensaje para `send()` o `sendEachForMulticast()`.
 */
function buildFcmMessage({
  token,
  tokens,
  title,
  body,
  type,
  entidad,
  extraData = {},
  soloData = false,
  channelId = "taxi_trip_channel",
}) {
  const clave = claveNotificacion(type, entidad);
  const notifId = idNotificacion(clave);

  const base = {
    data: {
      type,
      title,
      body,
      notifClave: clave,
      notifId: String(notifId),
      // Viaja en `data` para que la app pueda dibujarla en el canal correcto
      // cuando el mensaje es data-only: sin esto caía en el canal genérico
      // del sistema, que el usuario puede tener silenciado.
      channelId,
      ...extraData,
    },
    apns: {
      payload: {
        aps: {
          alert: { title, body },
          badge: 0,
          sound: "default",
          contentAvailable: true,
          mutableContent: true,
        },
      },
      headers: {
        "apns-priority": "10",
        // Reemplaza la anterior con la misma clave en vez de apilarla.
        "apns-collapse-id": clave,
      },
    },
    android: {
      priority: "high",
      // Colapsa los mensajes AÚN NO ENTREGADOS (p.ej. el teléfono estaba sin
      // red): llega solo el último de esta clave.
      //
      // FCM admite ~4 collapseKey distintos pendientes por dispositivo; pasado
      // eso descarta de forma impredecible. Como las claves son por entidad
      // (`viaje_<solicitud>`, `chat_<solicitud>`, `nueva_solicitud_<cliente>`),
      // un usuario normal tiene 1-3 a la vez.
      collapseKey: clave,
    },
  };

  if (!soloData) {
    base.notification = { title, body };
    base.android.notification = {
      channelId,
      sound: "default",
      priority: "high",
      // Reemplaza la anterior YA ENTREGADA en la bandeja.
      tag: clave,
    };
  }

  return tokens ? { ...base, tokens } : { ...base, token };
}

/**
 * Mensaje silencioso que le pide a la app borrar una notificación ya mostrada.
 *
 * Es data-only PURO (ni `notification{}` ni `aps.alert`): no tiene que verse
 * nada, solo desaparecer lo que ya está en la bandeja. iOS exige
 * `content-available: 1` con `apns-push-type: background` y prioridad 5 para
 * aceptar un push silencioso.
 *
 * @param {object} opts
 * @param {string} [opts.token]
 * @param {string[]} [opts.tokens]
 * @param {string} opts.clave Clave de la notificación a retirar.
 * @param {object} [opts.extraData]
 */
function buildRetiroMessage({ token, tokens, clave, extraData = {} }) {
  const base = {
    data: {
      type: "retirar_notificacion",
      notifClave: clave,
      notifId: String(idNotificacion(clave)),
      ...extraData,
    },
    apns: {
      payload: { aps: { "content-available": 1 } },
      headers: {
        "apns-push-type": "background",
        "apns-priority": "5",
      },
    },
    android: {
      priority: "high",
      collapseKey: `retiro_${clave}`,
    },
  };
  return tokens ? { ...base, tokens } : { ...base, token };
}

module.exports = {
  MAX_CLAVE_BYTES,
  claveNotificacion,
  idNotificacion,
  buildFcmMessage,
  buildRetiroMessage,
};
