/**
 * Cloud Function: Enviar notificación push FCM al cliente cuando cambia
 * el estado de una solicitud en Firestore.
 *
 * Trigger: onUpdate en /solicitudes/{solicitudId}
 *
 * Flujo:
 * 1. Detecta que el campo 'estado' cambió
 * 2. Obtiene el ID del cliente desde el documento de la solicitud
 * 3. Busca el token FCM del cliente en Firestore
 * 4. Envía la notificación push vía FCM (que llega a APNs en iOS)
 */

const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");

// Key de Google Directions: vive solo en Secret Manager, nunca se compila en
// el cliente. Configurar con: firebase functions:secrets:set GOOGLE_DIRECTIONS_KEY
const googleDirectionsKey = defineSecret("GOOGLE_DIRECTIONS_KEY");

initializeApp();

/**
 * Distancia en metros entre dos coordenadas (fórmula haversine).
 */
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (v) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * Máximo de operaciones por `WriteBatch` en Firestore. Superarlo hace fallar
 * el commit ENTERO, no las operaciones sobrantes.
 */
const MAX_OPS_POR_BATCH = 500;

/**
 * Aplica [aplicarOp] sobre [docs] repartiéndolos en batches de 500.
 *
 * Antes se metían todos los documentos en un solo `batch.commit()`. Con pocos
 * documentos funciona, pero si el job queda caído un tiempo y se acumulan más
 * de 500 vencidos, el commit falla completo y el barrido no limpia NADA — y
 * como el backlog solo crece, no se recupera solo.
 *
 * Los lotes se envían en serie a propósito: en paralelo, un backlog grande
 * dispararía cientos de commits simultáneos contra el mismo rango de
 * documentos, con contención y riesgo de rate limiting.
 */
async function commitEnLotes(db, docs, aplicarOp) {
  for (let i = 0; i < docs.length; i += MAX_OPS_POR_BATCH) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + MAX_OPS_POR_BATCH)) {
      aplicarOp(batch, doc);
    }
    await batch.commit();
  }
}

/**
 * Extrae {lat, lng} de un punto guardado como GeoPoint (con .latitude/.longitude)
 * o como mapa plano {lat, lng}.
 */
function extractLatLng(value) {
  if (!value || typeof value !== "object") return null;
  if (typeof value.latitude === "number" && typeof value.longitude === "number") {
    return { lat: value.latitude, lng: value.longitude };
  }
  if (typeof value.lat === "number" && typeof value.lng === "number") {
    return { lat: value.lat, lng: value.lng };
  }
  return null;
}

/**
 * Punto de recogida del cliente. Soporta las distintas formas en que la app
 * lo guarda: ubicacion_inicial (GeoPoint), cliente.ubicacion, origen.
 */
function extractPickupPoint(data) {
  return (
    extractLatLng(data.ubicacion_inicial) ||
    extractLatLng(data.cliente && data.cliente.ubicacion) ||
    extractLatLng(data.origen) ||
    null
  );
}

/**
 * Posición actual del conductor dentro de la solicitud.
 */
function extractConductorPoint(data) {
  const conductor = data.conductor;
  if (!conductor || typeof conductor !== "object") return null;
  if (typeof conductor.lat === "number" && typeof conductor.lng === "number") {
    return { lat: conductor.lat, lng: conductor.lng };
  }
  return extractLatLng(conductor.ubicacion);
}

/**
 * Busca el token FCM de un cliente en `usuarios` (y como respaldo en `cliente`).
 */
async function getClienteFcmToken(db, clienteId) {
  try {
    const userDoc = await db.collection("usuarios").doc(clienteId).get();
    if (userDoc.exists && userDoc.data().fcmToken) {
      return userDoc.data().fcmToken;
    }
  } catch (err) {
    console.error("Error buscando token en usuarios:", err);
  }

  try {
    const clienteDoc = await db.collection("cliente").doc(clienteId).get();
    if (clienteDoc.exists && clienteDoc.data().fcmToken) {
      return clienteDoc.data().fcmToken;
    }
  } catch (err) {
    console.error("Error buscando token en cliente:", err);
  }

  return null;
}

/**
 * Mapeo de estados a mensajes de notificación.
 * El título y cuerpo se envían como payload de la notificación push.
 */
const ESTADO_MENSAJES = {
  asignado: {
    title: "🚗 Conductor asignado",
    body: "Un conductor ha aceptado tu viaje. ¡Prepárate!",
  },
  "en espera": {
    title: "⏳ Esperando confirmación",
    body: "El conductor está esperando tu confirmación para iniciar el viaje.",
  },
  "en ruta": {
    title: "🚕 Viaje iniciado",
    body: "El viaje ha comenzado. ¡Disfruta el recorrido!",
  },
  completado: {
    title: "✅ Viaje completado",
    body: "Tu viaje ha finalizado. ¡Gracias por usar Ride!",
  },
  cancelado: {
    title: "❌ Viaje cancelado",
    body: "El viaje fue cancelado. Puedes solicitar uno nuevo.",
  },
  "sin respuesta": {
    title: "⚠️ Sin respuesta",
    body: "La solicitud quedó sin respuesta y fue cancelada.",
  },
};

/**
 * Normaliza el estado para coincidir con las claves del mapeo.
 */
function normalizeEstado(raw) {
  if (!raw || typeof raw !== "string") return "";
  const s = raw.toLowerCase().trim().replace(/_/g, " ").replace(/-/g, " ");

  if (s.includes("en ruta") || s.includes("enruta")) return "en ruta";
  if (s.includes("en espera") || s.includes("enespera")) return "en espera";
  if (s.includes("asignado") || s.includes("assigned")) return "asignado";
  if (s.includes("cancel")) return "cancelado";
  if (s.includes("sin respuesta") || s.includes("sinrespuesta")) return "sin respuesta";
  if (s.includes("complet") || s.includes("finaliz")) return "completado";

  return s;
}

/**
 * Extrae el ID del cliente desde el documento de la solicitud.
 * Soporta múltiples estructuras de datos.
 */
function extractClienteId(data) {
  // Estructura anidada: { cliente: { id: "...", uid: "..." } }
  if (data.cliente && typeof data.cliente === "object") {
    const id = data.cliente.id || data.cliente.uid || data.cliente.clienteId;
    if (id) return id;
  }
  // Campos planos
  return data.clienteId || data.userId || data.cliente_id || data.id_cliente || null;
}

/**
 * Extrae el ID del conductor asignado desde el documento de la solicitud.
 */
function extractConductorId(data) {
  if (data.conductor && typeof data.conductor === "object") {
    const id = data.conductor.id || data.conductor.uid || data.conductor.conductorId;
    if (id) return id;
  }
  return data.conductorId || null;
}

/**
 * Busca el token FCM de un conductor. Los conductores viven en `usuarios`
 * (mismo patrón que los clientes, distinguidos por `rol: 'conductor'`).
 */
async function getConductorFcmToken(db, conductorId) {
  try {
    const doc = await db.collection("usuarios").doc(conductorId).get();
    if (doc.exists && doc.data().fcmToken) {
      return doc.data().fcmToken;
    }
  } catch (err) {
    console.error("Error buscando token de conductor en usuarios:", err);
  }
  return null;
}

/**
 * Mensajes para el conductor cuando el CLIENTE provoca el cambio de estado
 * (confirma que va en camino al vehículo, o cancela el viaje). El resto de
 * estados los provoca el propio conductor desde su app, así que no necesita
 * que se le reenvíe push de su propia acción.
 */
const ESTADO_MENSAJES_CONDUCTOR = {
  "en camino": {
    title: "🚶 Cliente en camino",
    body: "El cliente confirmó que va en camino al vehículo.",
  },
  cancelado: {
    title: "❌ Viaje cancelado",
    body: "El cliente canceló el viaje.",
  },
};

/**
 * Cloud Function: Notifica por push al CONDUCTOR asignado cuando el cliente
 * confirma que va en camino o cancela el viaje. Simétrico a
 * [onSolicitudEstadoChange] (que notifica al cliente) — sin esto, el
 * conductor solo se enteraba vía notificación local mientras su app seguía
 * viva (foreground o los pocos segundos antes de que Android/iOS congelen
 * el proceso en background).
 */
exports.onSolicitudEstadoChangeConductor = onDocumentUpdated(
  {
    document: "solicitudes/{solicitudId}",
    region: "us-central1",
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    if (!beforeData || !afterData) return null;

    const estadoAnterior = normalizeEstado(beforeData.estado || beforeData.status || "");
    const estadoNuevo = normalizeEstado(afterData.estado || afterData.status || "");
    if (estadoAnterior === estadoNuevo) return null;

    const mensaje = ESTADO_MENSAJES_CONDUCTOR[estadoNuevo];
    if (!mensaje) return null;

    const conductorId = extractConductorId(afterData);
    if (!conductorId) return null;

    const db = getFirestore();
    const fcmToken = await getConductorFcmToken(db, conductorId);
    if (!fcmToken) {
      console.log(`No se encontró token FCM para el conductor: ${conductorId}`);
      return null;
    }

    const message = {
      token: fcmToken,
      notification: { title: mensaje.title, body: mensaje.body },
      data: {
        solicitudId: event.params.solicitudId,
        estado: estadoNuevo,
        type: "trip_status_change",
        title: mensaje.title,
        body: mensaje.body,
      },
      apns: {
        payload: {
          aps: {
            alert: { title: mensaje.title, body: mensaje.body },
            badge: 0,
            sound: "default",
            contentAvailable: true,
            mutableContent: true,
          },
        },
        headers: { "apns-priority": "10" },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "taxi_trip_channel",
          sound: "default",
          priority: "high",
        },
      },
    };

    try {
      const response = await getMessaging().send(message);
      console.log(`✅ Notificación enviada al conductor ${conductorId}: ${response}`);
    } catch (err) {
      console.error(`❌ Error enviando notificación a conductor: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function v2 — se dispara cuando un documento en /solicitudes cambia.
 */
exports.onSolicitudEstadoChange = onDocumentUpdated(
  {
    document: "solicitudes/{solicitudId}",
    region: "us-central1",
  },
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    if (!beforeData || !afterData) {
      console.log("Datos incompletos, saltando.");
      return null;
    }

    console.log("DEBUG: Datos del documento actual:", JSON.stringify(afterData));

    // Obtener estados normalizados
    const estadoAnterior = normalizeEstado(
      beforeData.estado || beforeData.status || ""
    );
    const estadoNuevo = normalizeEstado(
      afterData.estado || afterData.status || ""
    );

    // Solo proceder si el estado realmente cambió
    if (estadoAnterior === estadoNuevo) {
      return null;
    }

    console.log(
      `Solicitud ${event.params.solicitudId}: ${estadoAnterior} → ${estadoNuevo}`
    );

    // Verificar si tenemos un mensaje configurado para este estado
    const mensaje = ESTADO_MENSAJES[estadoNuevo];
    if (!mensaje) {
      console.log(`Sin mensaje configurado para estado: "${estadoNuevo}"`);
      return null;
    }

    // Extraer ID del cliente
    const clienteId = extractClienteId(afterData);
    if (!clienteId) {
      console.log("No se pudo extraer clienteId del documento");
      return null;
    }

    // Buscar el token FCM del cliente
    const db = getFirestore();
    let fcmToken = null;

    // Primero buscar en `usuarios`
    try {
      const userDoc = await db.collection("usuarios").doc(clienteId).get();
      if (userDoc.exists) {
        fcmToken = userDoc.data().fcmToken;
      }
    } catch (err) {
      console.error("Error buscando en usuarios:", err);
    }

    // Si no está en usuarios, buscar en `cliente`
    if (!fcmToken) {
      try {
        const clienteDoc = await db
          .collection("cliente")
          .doc(clienteId)
          .get();
        if (clienteDoc.exists) {
          fcmToken = clienteDoc.data().fcmToken;
        }
      } catch (err) {
        console.error("Error buscando en cliente:", err);
      }
    }

    if (!fcmToken) {
      console.log(`No se encontró token FCM para el cliente: ${clienteId}`);
      return null;
    }

    // Enviar notificación push vía FCM
    // Configuración específica para iOS (APNs)
    const fcmMessage = {
      token: fcmToken,
      notification: {
        title: mensaje.title,
        body: mensaje.body,
      },
      data: {
        solicitudId: event.params.solicitudId,
        estado: estadoNuevo,
        type: "trip_status_change",
        title: mensaje.title,
        body: mensaje.body,
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: mensaje.title,
              body: mensaje.body,
            },
            badge: 0,
            sound: "default",
            contentAvailable: true,
            mutableContent: true,
          },
        },
        headers: {
          "apns-priority": "10",
        },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "taxi_trip_channel",
          sound: "default",
          priority: "high",
        },
      },
    };

    try {
      const response = await getMessaging().send(fcmMessage);
      console.log(
        `✅ Notificación enviada al cliente ${clienteId}: ${response}`
      );
    } catch (err) {
      console.error(`❌ Error enviando notificación: ${err.message}`);

      // Si el token es inválido, limpiarlo para no gastar recursos
      if (
        err.code === "messaging/invalid-registration-token" ||
        err.code === "messaging/registration-token-not-registered"
      ) {
        console.log(`Limpiando token inválido de ${clienteId}`);
        try {
          await db
            .collection("usuarios")
            .doc(clienteId)
            .update({ fcmToken: null });
        } catch (_) { }
      }
    }

    return null;
  }
);

/**
 * Reúne los tokens FCM de todos los administradores.
 * Busca en la colección `administradores` y en `usuarios` con rol admin.
 */
async function getAdminTokens(db) {
  const tokens = new Set();

  try {
    const adminsSnap = await db.collection("administradores").get();
    adminsSnap.forEach((d) => {
      const t = d.data().fcmToken;
      if (t) tokens.add(t);
    });
  } catch (err) {
    console.error("Error leyendo administradores:", err);
  }

  for (const rol of ["admin", "administrador"]) {
    try {
      const snap = await db
        .collection("usuarios")
        .where("rol", "==", rol)
        .get();
      snap.forEach((d) => {
        const t = d.data().fcmToken;
        if (t) tokens.add(t);
      });
    } catch (err) {
      console.error(`Error leyendo usuarios rol=${rol}:`, err);
    }
  }

  return [...tokens];
}

/**
 * Cloud Function: Notifica a los administradores cuando un cliente solicita
 * activar el servicio de conductor (campo `solicitudConductor` pasa a true en
 * /usuarios/{uid}). Llega aunque la app del admin esté cerrada (push FCM/APNs).
 */
exports.onSolicitudConductorNueva = onDocumentUpdated(
  {
    document: "usuarios/{uid}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return null;

    const pidioAntes = before.solicitudConductor === true;
    const pideAhora = after.solicitudConductor === true;

    // Solo cuando pasa de false/ausente a true
    if (pidioAntes || !pideAhora) return null;

    const db = getFirestore();
    const tokens = await getAdminTokens(db);
    if (tokens.length === 0) {
      console.log("No hay tokens de administradores para notificar.");
      return null;
    }

    const nombre =
      [after.nombre, after.apellido]
        .filter((p) => p && String(p).trim())
        .join(" ")
        .trim() || "Un cliente";

    const title = "🚖 Nueva solicitud de conductor";
    const body = `${nombre} quiere activar el servicio de conductor.`;

    const message = {
      tokens: tokens,
      notification: { title, body },
      data: {
        type: "solicitud_conductor",
        uid: event.params.uid,
        title,
        body,
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
        headers: { "apns-priority": "10" },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "taxi_trip_channel",
          sound: "default",
          priority: "high",
        },
      },
    };

    try {
      const resp = await getMessaging().sendEachForMulticast(message);
      console.log(
        `✅ Notif. solicitud conductor: ${resp.successCount}/${tokens.length} enviadas.`
      );
    } catch (err) {
      console.error(`❌ Error enviando notif. a admins: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function: Notifica a los conductores cercanos cuando se crea una
 * solicitud nueva (estado "buscando"). Es el equivalente push del listener
 * en tiempo real de InicioConductorViewModel — ese listener solo funciona
 * con la app abierta; esta función llega aunque el conductor tenga la app
 * cerrada o esté usando otra app (Android/iOS), vía FCM/APNs.
 */
exports.onNuevaSolicitudCreada = onDocumentCreated(
  {
    document: "solicitudes/{solicitudId}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const estado = (data.estado || data.status || "").toString().toLowerCase().trim();
    if (!["buscando", "pending", "pendiente"].includes(estado)) {
      return null;
    }

    const pickup = extractPickupPoint(data);
    if (!pickup) {
      console.log("Solicitud sin ubicación de recogida, no se puede notificar.");
      return null;
    }

    const tipoVehiculoSolicitado = (data.tipoVehiculo || "").toString().toLowerCase().trim();
    const db = getFirestore();

    // Buscamos conductores "conectado" y "disponible" por separado (son
    // banderas equivalentes usadas indistintamente en distintas versiones
    // de la app) y los unimos por id para no duplicar.
    const candidatos = new Map();
    for (const campo of ["disponible", "conectado"]) {
      try {
        const snap = await db
          .collection("usuarios")
          .where("rol", "==", "conductor")
          .where(campo, "==", true)
          .get();
        snap.forEach((doc) => candidatos.set(doc.id, doc.data()));
      } catch (err) {
        console.error(`Error consultando conductores (${campo}):`, err);
      }
    }

    if (candidatos.size === 0) {
      console.log("No hay conductores conectados para notificar.");
      return null;
    }

    // La posición del conductor NO vive en `usuarios/{uid}.ubicacion`: ese
    // campo no lo escribe nadie (`FirebaseService.guardarUbicacionConductor`
    // no tiene llamadores y `TrackingService.enviarUbicacion` se niega
    // explícitamente a escribir GPS en el doc de usuario). El único lugar con
    // la posición es `conductores_conectados/{uid}`, que es lo que escribe
    // `InicioConductorViewmodel.guardarUbicacionConectado`.
    //
    // Mientras se leyó el campo inexistente, `extractLatLng` devolvía null
    // para TODOS los conductores y esta función terminaba siempre en
    // "Ningún conductor conectado está dentro del radio de 3 km": ningún
    // conductor recibía jamás un aviso de solicitud nueva.
    const ubicacionesPorUid = new Map();
    const uids = [...candidatos.keys()];
    for (let i = 0; i < uids.length; i += 100) {
      const refs = uids
        .slice(i, i + 100)
        .map((uid) => db.collection("conductores_conectados").doc(uid));
      try {
        const docs = await db.getAll(...refs);
        docs.forEach((doc) => {
          if (!doc.exists) return;
          const pos = extractLatLng((doc.data() || {}).ubicacion);
          if (pos) ubicacionesPorUid.set(doc.id, pos);
        });
      } catch (err) {
        console.error("Error leyendo conductores_conectados:", err);
      }
    }

    const cercanos = [];
    for (const [uid, conductorData] of candidatos) {
      const tipoConductor = (conductorData.tipoVehiculo || "").toString().toLowerCase().trim();
      if (tipoVehiculoSolicitado && tipoConductor && tipoConductor !== tipoVehiculoSolicitado) {
        continue;
      }
      const ubicacion = ubicacionesPorUid.get(uid);
      if (!ubicacion || !conductorData.fcmToken) continue;

      const distancia = haversineMeters(pickup.lat, pickup.lng, ubicacion.lat, ubicacion.lng);
      // Mismo radio que la lista visible en la app del conductor (3 km).
      if (distancia <= 3000) {
        cercanos.push({ uid, token: conductorData.fcmToken, distancia });
      }
    }

    if (cercanos.length === 0) {
      console.log("Ningún conductor conectado está dentro del radio de 3 km.");
      return null;
    }

    cercanos.sort((a, b) => a.distancia - b.distancia);
    const tokens = cercanos.slice(0, 20).map((c) => c.token);

    const title = "Solicitud entrante";
    const body = "Un cliente cerca de ti necesita servicio";

    const message = {
      tokens,
      notification: { title, body },
      data: {
        type: "nueva_solicitud",
        solicitudId: event.params.solicitudId,
        title,
        body,
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
        headers: { "apns-priority": "10" },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "taxi_trip_channel",
          sound: "default",
          priority: "high",
        },
      },
    };

    try {
      const resp = await getMessaging().sendEachForMulticast(message);
      console.log(
        `✅ Notif. nueva solicitud: ${resp.successCount}/${tokens.length} conductores notificados.`
      );
    } catch (err) {
      console.error(`❌ Error enviando notif. de nueva solicitud: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function: Notifica al cliente por push cuando el conductor está a
 * <= 70 m del punto de recogida, mientras la solicitud está en estado
 * "asignado" (tramo en el que el conductor se dirige hacia el cliente).
 * Complementa el aviso local de TripTrackingViewModel, que solo funciona
 * con la app del cliente abierta y en esa pantalla.
 */
exports.onConductorProximidadCliente = onDocumentUpdated(
  {
    document: "solicitudes/{solicitudId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return null;

    if (after.proximidadNotificada === true) return null;

    const estado = (after.estado || after.status || "").toString().toLowerCase().trim();
    if (estado !== "asignado") return null;

    const conductorPos = extractConductorPoint(after);
    const pickup = extractPickupPoint(after);
    if (!conductorPos || !pickup) return null;

    const distancia = haversineMeters(
      conductorPos.lat,
      conductorPos.lng,
      pickup.lat,
      pickup.lng
    );
    if (distancia > 70) return null;

    const clienteId = extractClienteId(after);
    if (!clienteId) return null;

    // Reclamar el aviso ANTES de enviarlo, en una transacción.
    //
    // El chequeo de `after.proximidadNotificada` de arriba no alcanza: esta
    // función se dispara con CADA update del documento y el conductor escribe
    // su GPS seguido, así que dos updates casi simultáneos producían dos
    // invocaciones concurrentes que leían el flag en `false` y ambas enviaban
    // la push — el cliente recibía "Tu conductor está cerca" dos veces (visto
    // en dispositivo real). Marcar el flag después del envío deja abierta toda
    // la ventana del `send()`.
    //
    // Con la transacción solo una invocación logra pasar de `false` a `true`;
    // las demás salen sin notificar.
    const dbProximidad = getFirestore();
    const solicitudRef = dbProximidad
      .collection("solicitudes")
      .doc(event.params.solicitudId);
    try {
      const reclamado = await dbProximidad.runTransaction(async (tx) => {
        const snap = await tx.get(solicitudRef);
        if (!snap.exists) return false;
        if (snap.data().proximidadNotificada === true) return false;
        tx.update(solicitudRef, { proximidadNotificada: true });
        return true;
      });
      if (!reclamado) return null;
    } catch (err) {
      console.error(`❌ Error reclamando aviso de proximidad: ${err.message}`);
      return null;
    }

    const db = getFirestore();
    const fcmToken = await getClienteFcmToken(db, clienteId);
    if (!fcmToken) {
      console.log(`No se encontró token FCM para el cliente: ${clienteId}`);
      return null;
    }

    const title = "🚗 Tu conductor está cerca";
    const body = "El conductor está por llegar. ¡Prepárate para abordar!";

    const message = {
      token: fcmToken,
      notification: { title, body },
      data: {
        type: "conductor_cerca",
        solicitudId: event.params.solicitudId,
        title,
        body,
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
        headers: { "apns-priority": "10" },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "taxi_trip_channel",
          sound: "default",
          priority: "high",
        },
      },
    };

    try {
      await getMessaging().send(message);
      console.log(`✅ Notif. proximidad enviada al cliente ${clienteId}`);
    } catch (err) {
      // El flag ya quedó reclamado arriba: si el envío falla no se reintenta.
      // Es deliberado — un aviso de proximidad perdido es preferible a
      // arriesgar el duplicado, y el cliente ve al conductor acercarse en el
      // mapa de todas formas.
      console.error(`❌ Error enviando notif. de proximidad: ${err.message}`);
    }

    return null;
  }
);

/**
 * Extrae del mapa `contraofertas` de una solicitud las entradas en estado
 * "pendiente_cliente", indexadas por clave `conductorId:valorRedondeado`
 * (mismo criterio de deduplicación que usa BuscandoTaxiViewModel del lado
 * del cliente): un mismo conductor con un valor distinto cuenta como una
 * contraoferta nueva.
 */
function extractPendingContraofertas(data) {
  const map = data && data.contraofertas;
  const result = new Map();
  if (!map || typeof map !== "object") return result;

  for (const [key, raw] of Object.entries(map)) {
    if (!raw || typeof raw !== "object") continue;
    if (raw.estado !== "pendiente_cliente") continue;
    const valor = typeof raw.valor === "number" ? raw.valor : null;
    if (valor == null) continue;
    const conductorId =
      (raw.conductor && (raw.conductor.id || raw.conductor.uid)) ||
      raw.conductorId ||
      key;
    const nombre =
      (raw.conductor && raw.conductor.nombre) || raw.conductorNombre || "Un conductor";
    result.set(`${conductorId}:${Math.round(valor)}`, { valor, nombre });
  }
  return result;
}

/**
 * Cloud Function: notifica al cliente por push cuando un conductor envía o
 * actualiza una contraoferta ("pendiente_cliente"). Antes esto solo se
 * mostraba con una notificación local
 * (BuscandoTaxiViewModel._mostrarNotificacionContraoferta), que no llega si
 * el cliente tiene la app en background/cerrada mientras espera.
 */
exports.onContraofertaCreada = onDocumentUpdated(
  {
    document: "solicitudes/{solicitudId}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return null;

    const beforeOfertas = extractPendingContraofertas(before);
    const afterOfertas = extractPendingContraofertas(after);

    // Compat: formato legacy de contraoferta única (sin mapa `contraofertas`).
    const beforeLegacy = before.contraoferta;
    const afterLegacy = after.contraoferta;
    const legacyEsNueva =
      afterLegacy &&
      afterLegacy.estado === "pendiente_cliente" &&
      typeof afterLegacy.valor === "number" &&
      !(
        beforeLegacy &&
        beforeLegacy.estado === "pendiente_cliente" &&
        beforeLegacy.valor === afterLegacy.valor
      );

    const nuevas = [...afterOfertas.keys()].filter(
      (key) => !beforeOfertas.has(key)
    );

    if (nuevas.length === 0 && !legacyEsNueva) return null;

    const clienteId = extractClienteId(after);
    if (!clienteId) return null;

    const db = getFirestore();
    const fcmToken = await getClienteFcmToken(db, clienteId);
    if (!fcmToken) {
      console.log(`No se encontró token FCM para el cliente: ${clienteId}`);
      return null;
    }

    // Notificar la contraoferta más barata entre las nuevas (mismo orden que
    // la lista que ve el cliente en su app).
    let valor = legacyEsNueva ? afterLegacy.valor : null;
    if (nuevas.length > 0) {
      const valores = nuevas.map((key) => afterOfertas.get(key).valor);
      const minNueva = Math.min(...valores);
      valor = valor == null ? minNueva : Math.min(valor, minNueva);
    }

    const valorTexto = Math.round(valor).toLocaleString("es-CO");
    const title = "💬 Contraoferta del conductor";
    const body = `Te proponen un nuevo valor: $${valorTexto}`;

    const message = buildFcmMessage({
      token: fcmToken,
      title,
      body,
      type: "contraoferta",
      extraData: { solicitudId: event.params.solicitudId },
    });

    try {
      await getMessaging().send(message);
      console.log(`✅ Notif. contraoferta enviada al cliente ${clienteId}`);
    } catch (err) {
      console.error(`❌ Error enviando notif. de contraoferta: ${err.message}`);
    }

    return null;
  }
);

/**
 * Arma un mensaje FCM con la config estándar de la app (APNs + canal Android
 * de alta prioridad). `token` puede ser un solo token (mensaje single-send)
 * o un array (usar con sendEachForMulticast).
 */
function buildFcmMessage({ token, tokens, title, body, type, extraData = {} }) {
  const base = {
    notification: { title, body },
    data: { type, title, body, ...extraData },
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
      headers: { "apns-priority": "10" },
    },
    android: {
      priority: "high",
      notification: {
        channelId: "taxi_trip_channel",
        sound: "default",
        priority: "high",
      },
    },
  };
  return tokens ? { ...base, tokens } : { ...base, token };
}

/**
 * Cloud Function: Notifica por push al destinatario de un mensaje de chat de
 * viaje (cliente ↔ conductor). Antes esto solo se mostraba con
 * flutter_local_notifications mientras la pantalla de chat/tracking del
 * destinatario seguía montada — con la app en background o cerrada, el
 * mensaje no se enteraba.
 */
exports.onTripChatMessageCreated = onDocumentCreated(
  {
    document: "solicitudes/{solicitudId}/mensajes/{mensajeId}",
    region: "us-central1",
  },
  async (event) => {
    const msg = event.data.data();
    if (!msg) return null;

    const senderId = msg.senderId;
    const texto = (msg.texto || msg.text || "").toString().trim();
    if (!senderId || !texto) return null;

    const db = getFirestore();
    const tripSnap = await db
      .collection("solicitudes")
      .doc(event.params.solicitudId)
      .get();
    if (!tripSnap.exists) return null;
    const trip = tripSnap.data();

    const clienteId = extractClienteId(trip);
    const conductorId = extractConductorId(trip);

    let recipientToken = null;
    let recipientLabel = "";
    if (senderId === clienteId && conductorId) {
      recipientToken = await getConductorFcmToken(db, conductorId);
      recipientLabel = "conductor";
    } else if (senderId === conductorId && clienteId) {
      recipientToken = await getClienteFcmToken(db, clienteId);
      recipientLabel = "cliente";
    } else {
      return null;
    }

    if (!recipientToken) {
      console.log(`Sin token FCM para notificar chat al ${recipientLabel}.`);
      return null;
    }

    // El nombre del conductor estaba hardcodeado como "Conductor": el cliente
    // recibía "💬 Conductor" en vez del nombre real, aunque el documento lo
    // trae denormalizado en `conductor.nombre` (lo escribe
    // `_buildConductorPayload` al aceptar). El lado contrario sí usaba el
    // nombre del cliente.
    const senderName =
      recipientLabel === "conductor"
        ? trip.cliente?.nombre || "Cliente"
        : trip.conductor?.nombre || "Conductor";

    const message = buildFcmMessage({
      token: recipientToken,
      title: `💬 ${senderName}`,
      body: texto,
      type: "trip_chat_message",
      extraData: { solicitudId: event.params.solicitudId },
    });

    try {
      await getMessaging().send(message);
      console.log(`✅ Notif. chat de viaje enviada al ${recipientLabel}.`);
    } catch (err) {
      console.error(`❌ Error enviando notif. de chat: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function: Notifica por push al usuario (cliente o conductor) cuando
 * el admin responde en el chat de soporte. El sentido usuario→admin ya viaja
 * por push (SoporteChatService llama a AdminFcmService directamente desde la
 * app); a este le faltaba el equivalente en el sentido admin→usuario.
 */
exports.onSoporteChatMensajeCreado = onDocumentCreated(
  {
    document: "soporte_chats/{userId}/mensajes/{mensajeId}",
    region: "us-central1",
  },
  async (event) => {
    const msg = event.data.data();
    if (!msg || msg.esAdmin !== true) return null;

    const texto = (msg.texto || "").toString().trim();
    if (!texto) return null;

    const db = getFirestore();
    const userId = event.params.userId;
    let fcmToken = null;
    try {
      const userDoc = await db.collection("usuarios").doc(userId).get();
      if (userDoc.exists) fcmToken = userDoc.data().fcmToken;
    } catch (err) {
      console.error("Error buscando token de usuario para soporte:", err);
    }
    if (!fcmToken) return null;

    const message = buildFcmMessage({
      token: fcmToken,
      title: "🛟 Soporte — Respuesta recibida",
      body: texto,
      // OJO: distinto de "soporte_chat" (ese type es para el push
      // usuario→admin y fcm_service.dart lo navega a AdminHubScreen). Este es
      // el sentido admin→usuario; un cliente/conductor no debe abrir esa
      // pantalla de admin al tocar la notificación.
      type: "soporte_chat_respuesta",
      extraData: { userId },
    });

    try {
      await getMessaging().send(message);
      console.log(`✅ Notif. respuesta de soporte enviada a ${userId}.`);
    } catch (err) {
      console.error(`❌ Error enviando notif. de soporte: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function: Notifica por push a TODOS los administradores cuando un
 * cliente activa el botón de pánico. Antes solo existía un listener local
 * (SoporteNotificationService.iniciarEscuchaEmergencias) que requería la app
 * del admin abierta — inaceptable para un evento de seguridad crítico.
 */
exports.onEmergenciaCreada = onDocumentCreated(
  {
    document: "emergencias/{emergenciaId}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const db = getFirestore();
    const tokens = await getAdminTokens(db);
    if (tokens.length === 0) return null;

    const motivos = Array.isArray(data.motivos) ? data.motivos.join(", ") : "";
    const body = motivos || "Un cliente activó el botón de pánico.";

    const message = buildFcmMessage({
      tokens,
      title: "🚨 EMERGENCIA — cliente en peligro",
      body,
      type: "emergencia",
      extraData: { emergenciaId: event.params.emergenciaId },
    });
    // Canal/urgencia máxima: una emergencia no debe sonar como una notificación normal.
    message.android.notification.channelId = "taxi_emergencia_channel";
    message.apns.headers["apns-priority"] = "10";

    try {
      const resp = await getMessaging().sendEachForMulticast(message);
      console.log(
        `✅ Notif. emergencia: ${resp.successCount}/${tokens.length} admins notificados.`
      );
    } catch (err) {
      console.error(`❌ Error enviando notif. de emergencia: ${err.message}`);
    }

    return null;
  }
);

/**
 * Cloud Function: Notifica por push a TODOS los administradores cuando se
 * crea un reporte sobre un conductor (problema reportado por el cliente).
 */
exports.onReporteCreado = onDocumentCreated(
  {
    document: "reportes/{reporteId}",
    region: "us-central1",
  },
  async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const db = getFirestore();
    const tokens = await getAdminTokens(db);
    if (tokens.length === 0) return null;

    const conductor = (data.conductor || "conductor").toString();
    const motivos = Array.isArray(data.motivos) ? data.motivos.join(", ") : "";
    const body = motivos || "Reporte enviado por un cliente.";

    const message = buildFcmMessage({
      tokens,
      title: `⚠️ Nuevo reporte — ${conductor}`,
      body,
      type: "reporte",
      extraData: { reporteId: event.params.reporteId },
    });

    try {
      const resp = await getMessaging().sendEachForMulticast(message);
      console.log(
        `✅ Notif. reporte: ${resp.successCount}/${tokens.length} admins notificados.`
      );
    } catch (err) {
      console.error(`❌ Error enviando notif. de reporte: ${err.message}`);
    }

    return null;
  }
);

// `debugPush` (función de diagnóstico que enviaba una push a un token
// arbitrario) se eliminó: era un `onRequest` sin verificación de auth ni App
// Check, así que cualquiera con la URL podía mandar notificaciones a cualquier
// token FCM suplantando a la app. Para probar pushes, usar la consola de
// Firebase Cloud Messaging (permite enviar a un token concreto) en vez de
// exponer un endpoint público.

/**
 * Cloud Function programada: cancela automáticamente solicitudes que llevan
 * demasiado tiempo en estado 'buscando' sin que ningún conductor las tome.
 *
 * Necesaria porque la cancelación por inactividad del lado del cliente (ver
 * buscando_taxi_view.dart) es un Timer en memoria de la app: si el usuario
 * mata la app desde el selector de apps recientes de Android antes de que
 * ese timer corra, el proceso Dart muere con él y nadie cancela la
 * solicitud — queda huérfana en Firestore hasta que el cliente reabra la
 * app (y auth_service.dart la cancele al detectarla). Este barrido corre
 * server-side sin depender en absoluto de que la app vuelva a abrirse.
 */
const SOLICITUD_BUSCANDO_TIMEOUT_MS = 3 * 60 * 1000; // 3 min sin conductor
// Retención de las solicitudes canceladas antes de borrarlas. La base guarda
// solo activas y terminadas; las canceladas se purgan, pero no al instante:
// 24 h dejan ventana para una disputa de soporte ("yo no cancelé") y para
// medir tasa de cancelación, y evitan cualquier carrera con un conductor que
// estuviera aceptando en ese mismo momento.
const CANCELADA_RETENCION_MS = 24 * 60 * 60 * 1000;

// Interruptor de seguridad de la purga: en `true` la función cuenta y loguea
// lo que borraría, pero no borra nada. Se usó así en el primer despliegue para
// medir el impacto real contra producción antes de una operación irreversible
// (la base no tiene Point-in-Time Recovery); el dry run reportó 3 documentos,
// todos canceladas de más de 24 h, y con eso validado se activó el borrado.
// Volver a ponerlo en `true` si alguna vez hay que auditar qué borraría.
const PURGA_CANCELADAS_DRY_RUN = false;

/**
 * Cloud Function HTTP: cancela una solicitud en estado 'buscando' cuando el
 * cliente cierra la app por completo (swipe en el selector de apps
 * recientes de Android).
 *
 * Se invoca desde un job de WorkManager encolado nativamente en
 * MainActivity.onTaskRemoved (ver android/app/.../MainActivity.kt +
 * CancelSolicitudWorker.kt). WorkManager persiste el job en su propia base
 * de datos y lo ejecuta aunque el proceso Android muera justo después —
 * a diferencia de cualquier Timer/callback en Dart, que muere con el
 * proceso sin llegar a escribir en Firestore.
 *
 * Validación: solo cancela si `clienteId` coincide con el dueño real de la
 * solicitud y si sigue en estado 'buscando' (evita tocar viajes ya
 * asignados/en curso ante una llamada tardía, duplicada o manipulada).
 */
exports.cancelarSolicitudPorCierreApp = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    const solicitudId = (
      req.query.solicitudId ||
      (req.body && req.body.solicitudId) ||
      ""
    ).toString();
    const clienteId = (
      req.query.clienteId ||
      (req.body && req.body.clienteId) ||
      ""
    ).toString();

    if (!solicitudId || !clienteId) {
      res.status(400).send("Faltan parámetros solicitudId/clienteId");
      return;
    }

    try {
      const db = getFirestore();
      const docRef = db.collection("solicitudes").doc(solicitudId);
      const doc = await docRef.get();

      if (!doc.exists) {
        res.status(200).send("no-op: solicitud no existe");
        return;
      }

      const data = doc.data();
      const estado = (data.estado || data.status || "").toString().toLowerCase();
      const rawCliente = data.cliente;
      const docClienteId = (
        (rawCliente && typeof rawCliente === "object"
          ? rawCliente.id || rawCliente.uid
          : null) ||
        data.clienteId ||
        data.userId ||
        ""
      ).toString();

      if (docClienteId !== clienteId) {
        res.status(403).send("no-op: cliente no coincide");
        return;
      }

      if (estado !== "buscando") {
        res.status(200).send(`no-op: estado actual '${estado}'`);
        return;
      }

      await docRef.update({
        estado: "cancelado",
        cancelledAt: FieldValue.serverTimestamp(),
        cancelReason: "app_cerrada",
      });
      console.log(
        `🛑 Solicitud ${solicitudId} cancelada por cierre de app (cliente ${clienteId}).`
      );

      // Borrado tras una breve gracia, igual que el resto de flujos de
      // cancelación (da tiempo a un accept en curso de un conductor).
      await new Promise((resolve) => setTimeout(resolve, 2000));
      await docRef.delete();

      res.status(200).send("ok: cancelada");
    } catch (err) {
      console.error("❌ Error en cancelarSolicitudPorCierreApp:", err.message);
      res.status(500).send(`error: ${err.message}`);
    }
  }
);

exports.cancelarSolicitudesBuscandoInactivas = onSchedule(
  {
    schedule: "every 2 minutes",
    region: "us-central1",
    timeoutSeconds: 60,
  },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(
      Date.now() - SOLICITUD_BUSCANDO_TIMEOUT_MS
    );

    let snap;
    try {
      snap = await db
        .collection("solicitudes")
        .where("estado", "==", "buscando")
        .where("createdAt", "<=", cutoff)
        .get();
    } catch (err) {
      console.error(
        "❌ Error consultando solicitudes 'buscando' vencidas:",
        err.message
      );
      return null;
    }

    if (snap.empty) return null;

    try {
      await commitEnLotes(db, snap.docs, (batch, doc) => {
        batch.update(doc.ref, {
          estado: "cancelado",
          cancelledAt: FieldValue.serverTimestamp(),
          cancelReason: "inactividad_timeout",
        });
      });
      console.log(
        `🛑 ${snap.size} solicitud(es) 'buscando' canceladas por inactividad.`
      );
    } catch (err) {
      console.error("❌ Error cancelando solicitudes vencidas:", err.message);
      return null;
    }

    // El borrado NO se hace acá. Antes esta función esperaba 5 s con un
    // `setTimeout` (tiempo de ejecución facturado, y contra un timeout de 60 s)
    // y borraba solo las que ella misma acababa de cancelar — las canceladas
    // por el cliente quedaban para siempre. Ahora lo hace
    // `purgarSolicitudesCanceladas`, que barre TODAS las canceladas por
    // igual, sea quien sea que las canceló.

    return null;
  }
);

// Purga las solicitudes canceladas: la colección debe guardar solo viajes
// activos y terminados. Cubre las tres formas de cancelar —el botón del
// cliente, el corte por inactividad de la app y el timeout de
// `cancelarSolicitudesBuscandoInactivas`— porque filtra por estado, no por
// quién canceló.
//
// Se hace server-side y no desde la app a propósito: `firestore.rules` tiene
// `allow delete: if false` en `solicitudes` y así se queda. La base de
// producción no tiene Point-in-Time Recovery, así que un borrado duro es
// irrecuperable; dárselo al cliente sería superficie de ataque nueva para algo
// que el Admin SDK ya puede hacer sin pasar por las reglas. Además, borrar en
// el momento de cancelar compite con un conductor que estuviera aceptando en
// ese instante — la retención de 24 h cierra esa carrera por completo.
//
// Cada 30 min alcanza de sobra para una retención de 24 h y mantiene el costo
// en ~48 lecturas/día cuando no hay nada que borrar.
exports.purgarSolicitudesCanceladas = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "us-central1",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(Date.now() - CANCELADA_RETENCION_MS);

    let snap;
    try {
      snap = await db
        .collection("solicitudes")
        .where("estado", "==", "cancelado")
        .where("cancelledAt", "<=", cutoff)
        .get();
    } catch (err) {
      console.error(
        "❌ Error consultando solicitudes canceladas a purgar:",
        err.message
      );
      return null;
    }

    if (snap.empty) {
      console.log("✅ Sin solicitudes canceladas de más de 24 h que purgar.");
      return null;
    }

    if (PURGA_CANCELADAS_DRY_RUN) {
      console.log(
        `🔎 DRY RUN: se borrarían ${snap.size} solicitud(es) cancelada(s) ` +
          `de más de 24 h. Ids: ${snap.docs
            .slice(0, 20)
            .map((d) => d.id)
            .join(", ")}${snap.size > 20 ? " …" : ""}`
      );
      return null;
    }

    try {
      await commitEnLotes(db, snap.docs, (batch, doc) => batch.delete(doc.ref));
      console.log(
        `🗑️ ${snap.size} solicitud(es) cancelada(s) purgada(s) (>24 h).`
      );
    } catch (err) {
      console.error("❌ Error purgando solicitudes canceladas:", err.message);
    }

    return null;
  }
);

// Corte server-side de membresías de conductor vencidas. Antes de esto, el
// único mecanismo era un Timer en InicioConductorView.dart que solo corre si
// el conductor tiene la app abierta: si el proceso muere en background (común
// en gama baja), `membresia` quedaba en 'activa' indefinidamente y
// `aceptarSolicitud()` no revalidaba vencimiento, dejando aceptar viajes gratis.
// Mismos campos que revoca el admin manualmente (`admin_home_screen.dart`) y
// que el propio corte local (`_expirarMembresia` en InicioConductorView.dart),
// para que cualquiera de los tres caminos deje al conductor en el mismo estado.
exports.expirarMembresiasVencidas = onSchedule(
  {
    schedule: "every 30 minutes",
    region: "us-central1",
    timeoutSeconds: 60,
  },
  async () => {
    const db = getFirestore();
    const ahora = Timestamp.now();

    let snap;
    try {
      snap = await db
        .collection("usuarios")
        .where("membresia", "==", "activa")
        .where("membresiaVence", "<=", ahora)
        .get();
    } catch (err) {
      console.error(
        "❌ Error consultando membresías vencidas:",
        err.message
      );
      return null;
    }

    if (snap.empty) return null;

    try {
      await commitEnLotes(db, snap.docs, (batch, doc) => {
        batch.update(doc.ref, {
          membresia: "",
          servicioActivo: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      console.log(
        `🛑 ${snap.size} membresía(s) de conductor expiradas por vencimiento.`
      );
    } catch (err) {
      console.error("❌ Error expirando membresías vencidas:", err.message);
    }

    return null;
  }
);

/**
 * Callable: proxy server-side de Google Directions API.
 *
 * Reemplaza la key hardcodeada que antes vivía en
 * lib/features/trip_tracking_cliente/services/map_service.dart (extraíble
 * del APK/IPA por cualquiera vía reversing). Acá la key nunca se compila en
 * el cliente: se guarda en Secret Manager y solo existe en memoria del
 * proceso de la función.
 *
 * Requiere sesión de Firebase Auth (cliente o conductor) para evitar que un
 * tercero use este proxy como Directions API gratis a costa de tu cuota.
 */
exports.getDirectionsRoute = onCall(
  { region: "us-central1", secrets: [googleDirectionsKey], timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Se requiere sesión iniciada.");
    }

    const { originLat, originLng, destLat, destLng } = request.data || {};
    if (
      typeof originLat !== "number" ||
      typeof originLng !== "number" ||
      typeof destLat !== "number" ||
      typeof destLng !== "number"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "originLat/originLng/destLat/destLng son requeridos y deben ser numéricos."
      );
    }

    const url = new URL(
      "https://maps.googleapis.com/maps/api/directions/json"
    );
    url.searchParams.set("origin", `${originLat},${originLng}`);
    url.searchParams.set("destination", `${destLat},${destLng}`);
    url.searchParams.set("mode", "driving");
    url.searchParams.set("units", "metric");
    url.searchParams.set("alternatives", "false");
    url.searchParams.set("key", googleDirectionsKey.value());

    let resp;
    try {
      resp = await fetch(url, { signal: AbortSignal.timeout(6000) });
    } catch (err) {
      throw new HttpsError(
        "unavailable",
        `No se pudo contactar Directions API: ${err.message}`
      );
    }

    if (!resp.ok) {
      throw new HttpsError(
        "unavailable",
        `Directions API respondió ${resp.status}`
      );
    }

    const body = await resp.json();
    const route = body.routes && body.routes[0];
    const encoded = route && route.overview_polyline && route.overview_polyline.points;
    if (!encoded) {
      throw new HttpsError("not-found", "No se encontró una ruta.");
    }

    return { encodedPolyline: encoded };
  }
);

// Centro aproximado de Ocaña (Norte de Santander) + radio en metros que cubre
// el casco urbano y alrededores cercanos (Libano al norte, Apartaderos al
// sur, El Hatillo/Venadillo al este) según el mapa de referencia del cliente.
const OCANA_CENTER = { lat: 8.2488503, lng: -73.3471543 };
const OCANA_RADIUS_METERS = 9000;

/**
 * Callable: Google Places Autocomplete restringido al radio de Ocaña.
 *
 * Evita que el buscador de destino sugiera direcciones de otra ciudad (lo
 * que confunde al usuario en una app de alcance local). `strictbounds=true`
 * hace que Google descarte resultados fuera del círculo en vez de solo
 * "preferirlos" (locationBias sin strict permitiría igual resultados
 * lejanos si no hay nada cerca que calce con el texto).
 *
 * Solo devuelve descripción + placeId (no coordenadas): pedir Place Details
 * por cada sugerencia mientras el usuario todavía escribe multiplicaría el
 * costo por nada; los detalles se piden una sola vez, cuando toca una.
 */
exports.searchPlacesOcana = onCall(
  { region: "us-central1", secrets: [googleDirectionsKey], timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Se requiere sesión iniciada.");
    }

    const query = ((request.data || {}).query || "").toString().trim();
    if (query.length < 2) {
      return { predictions: [] };
    }

    const url = new URL(
      "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    );
    url.searchParams.set("input", query);
    url.searchParams.set("location", `${OCANA_CENTER.lat},${OCANA_CENTER.lng}`);
    url.searchParams.set("radius", String(OCANA_RADIUS_METERS));
    url.searchParams.set("strictbounds", "true");
    url.searchParams.set("components", "country:co");
    url.searchParams.set("language", "es");
    url.searchParams.set("key", googleDirectionsKey.value());

    let resp;
    try {
      resp = await fetch(url, { signal: AbortSignal.timeout(6000) });
    } catch (err) {
      throw new HttpsError(
        "unavailable",
        `No se pudo contactar Places API: ${err.message}`
      );
    }

    if (!resp.ok) {
      throw new HttpsError("unavailable", `Places API respondió ${resp.status}`);
    }

    const body = await resp.json();
    if (body.status !== "OK" && body.status !== "ZERO_RESULTS") {
      throw new HttpsError(
        "internal",
        `Places API status ${body.status}: ${body.error_message || ""}`
      );
    }

    const predictions = (body.predictions || []).map((p) => ({
      placeId: p.place_id,
      description: p.description,
      mainText: (p.structured_formatting || {}).main_text || p.description,
      secondaryText: (p.structured_formatting || {}).secondary_text || "",
    }));

    return { predictions };
  }
);

/**
 * Callable: Place Details — resuelve lat/lng + dirección formateada de un
 * placeId devuelto por searchPlacesOcana. Se llama solo cuando el usuario
 * toca una sugerencia, no en cada tecla.
 */
exports.getPlaceDetails = onCall(
  { region: "us-central1", secrets: [googleDirectionsKey], timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Se requiere sesión iniciada.");
    }

    const placeId = ((request.data || {}).placeId || "").toString().trim();
    if (!placeId) {
      throw new HttpsError("invalid-argument", "placeId es requerido.");
    }

    const url = new URL("https://maps.googleapis.com/maps/api/place/details/json");
    url.searchParams.set("place_id", placeId);
    url.searchParams.set("fields", "geometry,formatted_address,name");
    url.searchParams.set("language", "es");
    url.searchParams.set("key", googleDirectionsKey.value());

    let resp;
    try {
      resp = await fetch(url, { signal: AbortSignal.timeout(6000) });
    } catch (err) {
      throw new HttpsError(
        "unavailable",
        `No se pudo contactar Places API: ${err.message}`
      );
    }

    if (!resp.ok) {
      throw new HttpsError("unavailable", `Places API respondió ${resp.status}`);
    }

    const body = await resp.json();
    if (body.status !== "OK") {
      throw new HttpsError(
        "not-found",
        `Places API status ${body.status}: ${body.error_message || ""}`
      );
    }

    const result = body.result || {};
    const location = (result.geometry || {}).location;
    if (!location) {
      throw new HttpsError("not-found", "El lugar no tiene coordenadas.");
    }

    return {
      lat: location.lat,
      lng: location.lng,
      formattedAddress: result.formatted_address || "",
      name: result.name || "",
    };
  }
);
