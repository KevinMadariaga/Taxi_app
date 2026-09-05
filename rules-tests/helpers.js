import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

const aqui = dirname(fileURLToPath(import.meta.url));
const REGLAS = join(aqui, '..', 'firestore.rules');

/** UIDs fijos para que los tests se lean como una historia. */
export const CLIENTE = 'cliente-1';
export const OTRO_CLIENTE = 'cliente-2';
export const CONDUCTOR = 'conductor-1';
export const OTRO_CONDUCTOR = 'conductor-2';
export const ADMIN = 'admin-1';

export async function crearEntorno() {
  return initializeTestEnvironment({
    projectId: 'demo-taxi-rules',
    firestore: {
      rules: readFileSync(REGLAS, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
}

/**
 * Siembra los documentos de los que dependen las reglas para clasificar a
 * quien hace la petición: `isConductorRole` e `isAdminRole` leen el mismo
 * campo `usuarios/{uid}.rol` (no una colección `administradores` aparte —
 * ese doc se sigue sembrando solo porque algunos tests prueban sus propias
 * reglas de escritura, ya sin relación con el rol de admin).
 *
 * Se escribe con `withSecurityRulesDisabled` porque es el montaje del
 * escenario, no parte de lo que se está probando.
 */
export async function sembrarActores(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`usuarios/${CLIENTE}`).set({ rol: 'cliente', nombre: 'Kevin' });
    await db.doc(`usuarios/${OTRO_CLIENTE}`).set({ rol: 'cliente' });
    // `membresia: 'activa'` en CONDUCTOR: desde la auditoría de seguridad,
    // `solicitudes.membresiaVigente()` exige esto en el servidor para poder
    // pasar a 'asignado' — mismo chequeo que ya hacía
    // `InicioConductorViewModel.aceptarSolicitud` en su transacción, ahora
    // también en las reglas. OTRO_CONDUCTOR se deja SIN membresía a
    // propósito: es el conductor "sin membresía activa" de los tests
    // negativos de esa misma regla.
    await db.doc(`usuarios/${CONDUCTOR}`).set({ rol: 'conductor', membresia: 'activa' });
    await db.doc(`usuarios/${OTRO_CONDUCTOR}`).set({ rol: 'conductor' });
    await db.doc(`usuarios/${ADMIN}`).set({ rol: 'admin' });
    await db.doc(`administradores/${ADMIN}`).set({ nombre: 'Admin' });
  });
}

export async function sembrar(testEnv, ruta, datos) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(ruta).set(datos);
  });
}

export const comoAnonimo = (env) => env.unauthenticatedContext().firestore();
export const como = (env, uid) => env.authenticatedContext(uid).firestore();

/** Documento de solicitud con la forma que escribe `SolicitudRepositoryImpl`. */
export function solicitud({ clienteId = CLIENTE, estado = 'buscando', conductorId } = {}) {
  const doc = {
    cliente: { id: clienteId, nombre: 'Kevin' },
    estado,
    tarifa: { total: 12000 },
  };
  if (conductorId) doc.conductor = { id: conductorId };
  return doc;
}

export { assertFails, assertSucceeds };
