// Queries de COLECCIÓN que hace la app.
//
// Firestore no filtra una query por reglas: la rechaza entera si no puede
// demostrar, a partir de los filtros, que todos los documentos que devolvería
// son legibles. Por eso un documento que sí se puede leer de a uno no implica
// que la query que lo busca vaya a pasar.
//
// Estas son las queries reales del código, cada una con su origen. Si alguna
// falla, ese flujo se rompe en el momento de desplegar las reglas endurecidas.

import { test, describe, before, after, beforeEach } from 'node:test';
import {
  crearEntorno, sembrarActores, sembrar, como, solicitud,
  assertFails, assertSucceeds,
  CLIENTE, OTRO_CLIENTE, CONDUCTOR, OTRO_CONDUCTOR, ADMIN,
} from './helpers.js';

let env;
before(async () => { env = await crearEntorno(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarActores(env);
  // Un poco de todo: propias, ajenas, abiertas y asignadas.
  await sembrar(env, 'solicitudes/propia-buscando', solicitud());
  await sembrar(env, 'solicitudes/propia-completada', solicitud({ estado: 'completado' }));
  await sembrar(env, 'solicitudes/ajena-buscando', solicitud({ clienteId: OTRO_CLIENTE }));
  await sembrar(env, 'solicitudes/mia-asignada',
    solicitud({ clienteId: OTRO_CLIENTE, estado: 'en ruta', conductorId: CONDUCTOR }));
  await sembrar(env, 'solicitudes/ajena-asignada',
    solicitud({ clienteId: OTRO_CLIENTE, estado: 'en ruta', conductorId: OTRO_CONDUCTOR }));
});

describe('queries del cliente', () => {
  // HistorialClienteViewModel.cargarHistorial
  test('historial del cliente: where cliente.id == propio', async () => {
    const snap = await assertSucceeds(
      como(env, CLIENTE).collection('solicitudes').where('cliente.id', '==', CLIENTE).get(),
    );
    // Debe traer solo las suyas.
    for (const d of snap.docs) {
      if (d.data().cliente.id !== CLIENTE) throw new Error('trajo una solicitud ajena');
    }
  });

  // CrearSolicitudUseCase -> SolicitudRepositoryImpl.buscarActivaDeCliente
  test('guard anti-duplicados: cliente.id == propio + estado whereIn activos', async () => {
    await assertSucceeds(
      como(env, CLIENTE).collection('solicitudes')
        .where('cliente.id', '==', CLIENTE)
        .where('estado', 'in', ['buscando', 'pending', 'pendiente', 'asignado',
          'en espera', 'en camino', 'en ruta'])
        .limit(1)
        .get(),
    );
  });

  test('un cliente NO puede pedir el historial de otro', async () => {
    await assertFails(
      como(env, CLIENTE).collection('solicitudes').where('cliente.id', '==', OTRO_CLIENTE).get(),
    );
  });
});

describe('queries del conductor', () => {
  // PendingSolicitudesController.subscribe
  test('lista de pendientes: estado whereIn buscando', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).collection('solicitudes')
        .where('estado', 'in', ['buscando', 'pending', 'pendiente'])
        .get(),
    );
  });

  // InicioConductorViewmodel._subscribeAssignedToMe (con el filtro de estado
  // que se le agregó para no descargar el historial completo).
  test('asignadas a mí: conductor.id == propio + estado whereIn activos', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).collection('solicitudes')
        .where('conductor.id', '==', CONDUCTOR)
        .where('estado', 'in', ['asignado', 'en espera', 'en camino', 'en ruta'])
        .get(),
    );
  });

  // HistorialConductorViewModel / ConductorProfileController: historial y
  // ratings. Query SIN filtro de estado, solo por conductor.id.
  test('historial del conductor: where conductor.id == propio', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).collection('solicitudes')
        .where('conductor.id', '==', CONDUCTOR)
        .get(),
    );
  });

  // Hay conductores en producción marcados solo con el campo legacy
  // `tipoUsuario` y sin `rol` — el propio código los reconoce así
  // (`initial_screen_resolver.dart:148-158`). Con `isConductorRole()`
  // mirando solo `rol`, la app los llevaba a su home y la lista quedaba
  // vacía con permission-denied.
  test('un conductor marcado solo con tipoUsuario ve las pendientes', async () => {
    await sembrar(env, `usuarios/${OTRO_CONDUCTOR}`, {
      tipoUsuario: 'conductor', nombre: 'Legacy',
    });
    await assertSucceeds(
      como(env, OTRO_CONDUCTOR).collection('solicitudes')
        .where('estado', 'in', ['buscando', 'pending', 'pendiente'])
        .get(),
    );
  });

  test('un cliente NO puede listar las pendientes', async () => {
    await assertFails(
      como(env, CLIENTE).collection('solicitudes')
        .where('estado', 'in', ['buscando', 'pending', 'pendiente'])
        .get(),
    );
  });

  test('un conductor NO puede pedir los viajes de otro', async () => {
    await assertFails(
      como(env, CONDUCTOR).collection('solicitudes')
        .where('conductor.id', '==', OTRO_CONDUCTOR)
        .get(),
    );
  });

  // Un conductor sin filtros pediría también las asignadas a otros.
  test('un conductor NO puede listar la colección entera', async () => {
    await assertFails(como(env, CONDUCTOR).collection('solicitudes').get());
  });
});

describe('queries del admin', () => {
  // GestionConductoresViewModel: lista conductores.
  test('admin lista usuarios con rol conductor', async () => {
    await assertSucceeds(
      como(env, ADMIN).collection('usuarios').where('rol', '==', 'conductor').get(),
    );
  });

  // AdminHomeScreen hace `usuariosRef.snapshots()` SIN filtro y reparte el
  // resultado entre las pestañas Conductores y Clientes. Con la regla
  // original (admin solo lee conductores) Firestore rechazaba la query entera
  // y el panel quedaba vacío; por eso se amplió la lectura.
  test('admin lista usuarios sin filtrar (lo que hace AdminHomeScreen)', async () => {
    await assertSucceeds(como(env, ADMIN).collection('usuarios').get());
  });

  test('un no-admin sigue sin poder listar usuarios', async () => {
    await assertFails(como(env, CLIENTE).collection('usuarios').get());
    await assertFails(como(env, CONDUCTOR).collection('usuarios').get());
  });

  // SoporteNotificationService.iniciarEscuchaReportes / Emergencias
  test('admin escucha reportes y emergencias', async () => {
    await sembrar(env, 'reportes/r1', { clienteId: CLIENTE });
    await sembrar(env, 'emergencias/e1', { userId: CLIENTE });
    await assertSucceeds(como(env, ADMIN).collection('reportes').where('visto', '==', false).get());
    await assertSucceeds(como(env, ADMIN).collection('emergencias').get());
  });
});
