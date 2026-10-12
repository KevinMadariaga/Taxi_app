// Idempotencia de los triggers y límite de llamadas por usuario.
//
// Firestore entrega los eventos "al menos una vez": en casos raros el mismo
// cambio llega dos veces y, sin esto, el aviso salía duplicado o la
// calificación se sumaba dos veces al promedio. Y un callable sin límite
// deja que una cuenta comprometida mande cientos de promociones seguidas.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const DIA_MS = 24 * 60 * 60 * 1000;

/** Cuánto se guarda la marca de un evento ya procesado. Los reenvíos de
 * Firestore llegan en minutos; 3 días sobra. Las borra
 * `purgarRegistrosVencidos` (dentro de `purgarSolicitudesCanceladas`). */
const RETENCION_EVENTO_MS = 3 * DIA_MS;

/**
 * `true` la primera vez que se ve este evento en el trigger [nombre];
 * `false` si ya se procesó (y entonces no hay que volver a enviar/sumar).
 *
 * El id de un CloudEvent es el mismo para todos los triggers que escuchan
 * el mismo documento, por eso la marca lleva también el nombre.
 *
 * Va justo antes de enviar o escribir, no al principio del trigger: los
 * triggers de `solicitudes` se disparan con cada escritura de la ubicación
 * del conductor y una marca por ejecución sería una escritura extra cada
 * pocos segundos.
 */
async function unaVez(event, nombre, { db = getFirestore(), ahora = Date.now() } = {}) {
  const id = event && event.id;
  if (!id) return true; // sin id no hay con qué deduplicar: mejor avisar
  try {
    await db
      .collection("eventos_procesados")
      .doc(`${nombre}:${id}`)
      .create({
        nombre,
        creadoEn: FieldValue.serverTimestamp(),
        expiraEn: Timestamp.fromMillis(ahora + RETENCION_EVENTO_MS),
      });
    return true;
  } catch (err) {
    // 6 = ALREADY_EXISTS: el mismo evento ya pasó por aquí.
    if (err && (err.code === 6 || /already.?exists/i.test(String(err.message)))) {
      console.log(`↩️ ${nombre}: evento ${id} repetido, se omite.`);
      return false;
    }
    // Falla de Firestore al marcar: se procesa igual. Mejor un aviso
    // repetido (lo que pasaba antes) que uno perdido.
    console.error(`⚠️ ${nombre}: no se pudo marcar el evento ${id}:`, err.message);
    return true;
  }
}

/**
 * Decide si una llamada entra en el cupo: [estado] es lo guardado
 * (`{inicio, usados}` o nada). Ventana fija de [ventanaMs] desde la primera
 * llamada.
 */
function evaluarCupo(estado, { ahora, max, ventanaMs }) {
  const vigente = estado && typeof estado.inicio === "number" &&
    ahora - estado.inicio < ventanaMs;
  const inicio = vigente ? estado.inicio : ahora;
  const usados = vigente ? Number(estado.usados) || 0 : 0;
  if (usados >= max) {
    return { permitido: false, reintentarEnMs: inicio + ventanaMs - ahora };
  }
  return { permitido: true, nuevo: { inicio, usados: usados + 1 } };
}

/**
 * Gasta una llamada del cupo [clave] (p. ej. `enviarPromocion:<uid>`).
 * Devuelve `{permitido, reintentarEnMs}`; en transacción para que dos
 * llamadas simultáneas no se cuelen las dos con el último cupo.
 */
async function consumirCupo(clave, { max, ventanaMs, db = getFirestore(), ahora = Date.now() }) {
  const ref = db.collection("limites").doc(clave);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const r = evaluarCupo(snap.exists ? snap.data() : null, { ahora, max, ventanaMs });
    if (r.permitido) {
      tx.set(ref, {
        ...r.nuevo,
        expiraEn: Timestamp.fromMillis(r.nuevo.inicio + ventanaMs),
      });
    }
    return r;
  });
}

module.exports = { unaVez, evaluarCupo, consumirCupo, RETENCION_EVENTO_MS };
