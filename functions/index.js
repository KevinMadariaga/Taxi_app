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

const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onRequest } = require("firebase-functions/v2/https");

initializeApp();

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
  "en camino": {
    title: "Cliente en camino",
    body: "Espera que llegue el cliente al vehiculo.",
  },
  "en ruta": {
    title: "🚕 Viaje iniciado",
    body: "El viaje ha comenzado. ¡Disfruta el recorrido!",
  },
  completado: {
    title: "✅ Viaje completado",
    body: "Tu viaje ha finalizado. ¡Gracias por usar Taxi Ya!",
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
  if (s.includes("en camino") || s.includes("encam")) return "en camino";
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
            badge: 1,
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
 * Función de diagnóstico: Permite enviar una notificación de prueba a un token.
 * URL: https://[region]-[project].cloudfunctions.net/debugPush?token=[FCM_TOKEN]
 */
exports.debugPush = onRequest({ region: "us-central1" }, async (req, res) => {
  const token = req.query.token;
  if (!token) {
    res.status(400).send("Falta el parámetro 'token'");
    return;
  }

  const message = {
    token: token,
    notification: {
      title: "Prueba de Conexión",
      body: "Si ves esto, la comunicación Firebase -> iOS es exitosa.",
    },
    data: {
      type: "debug",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          contentAvailable: true,
        },
      },
    },
  };

  try {
    const response = await getMessaging().send(message);
    res.status(200).send(`✅ Mensaje enviado: ${response}`);
  } catch (err) {
    res.status(500).send(`❌ Error: ${err.message}`);
  }
});
