// Reglas de la búsqueda de conductor que no dependen de Firebase: cuándo
// repartir de nuevo una solicitud, cuándo vence y cuándo se activa un viaje
// programado. Módulo puro para testearlo con `node --test`.

/** Sin "Avísame": a los 15 min sin conductor la búsqueda se cancela. */
const TIMEOUT_BUSQUEDA_MS = 15 * 60 * 1000;

/** Con "Avísame" (o un viaje programado) el pasajero no está mirando la
 * pantalla: se le da el doble de margen antes de rendirse. */
const TIMEOUT_CON_AVISO_MS = 30 * 60 * 1000;

/** Un viaje programado sale a buscar conductor con esta anticipación. */
const ANTICIPACION_PROGRAMADA_MS = 10 * 60 * 1000;

function tipoDe(data) {
  return String((data && data.tipoVehiculo) || "").toLowerCase().trim();
}

/**
 * ¿Hay que volver a avisar a los conductores? Solo si la búsqueda ARRANCA por
 * un programado que se activa, o si cambió el vehículo a mitad de búsqueda
 * (los conductores del tipo nuevo nunca recibieron el aviso). Los estados ya
 * vienen normalizados.
 */
function debeRepartirDeNuevo(estadoAntes, estadoDespues, antes, despues) {
  if (estadoDespues !== "buscando") return false;
  if (estadoAntes === "programada") return true;
  return estadoAntes === "buscando" && tipoDe(antes) !== tipoDe(despues);
}

/** Motivo de cancelación si [data] ya venció, o `null` si sigue a tiempo. */
function motivoDeVencimiento(data, creadaEnMs, ahoraMs) {
  const conAviso = data && data.avisarAlEncontrar === true;
  const limite = conAviso ? TIMEOUT_CON_AVISO_MS : TIMEOUT_BUSQUEDA_MS;
  if (ahoraMs - creadaEnMs < limite) return null;
  return conAviso ? "sin_conductor" : "inactividad_timeout";
}

module.exports = {
  TIMEOUT_BUSQUEDA_MS,
  TIMEOUT_CON_AVISO_MS,
  ANTICIPACION_PROGRAMADA_MS,
  debeRepartirDeNuevo,
  motivoDeVencimiento,
};
