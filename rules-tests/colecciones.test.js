// Reglas del resto de colecciones: perfiles, presencia, ubicaciones
// guardadas, soporte y reportes.

import { test, describe, before, after, beforeEach } from 'node:test';
import {
  crearEntorno, sembrarActores, sembrar, como, comoAnonimo,
  assertFails, assertSucceeds,
  CLIENTE, OTRO_CLIENTE, CONDUCTOR, ADMIN,
} from './helpers.js';

let env;
before(async () => { env = await crearEntorno(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarActores(env);
});

describe('usuarios', () => {
  test('cada uno lee su propio perfil', async () => {
    await assertSucceeds(como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).get());
  });

  test('nadie lee el perfil de otro cliente', async () => {
    await assertFails(como(env, CLIENTE).doc(`usuarios/${OTRO_CLIENTE}`).get());
  });

  test('un admin lee el perfil de un conductor', async () => {
    await assertSucceeds(como(env, ADMIN).doc(`usuarios/${CONDUCTOR}`).get());
  });

  test('un admin lee el perfil de un cliente (lo necesita su panel)', async () => {
    await assertSucceeds(como(env, ADMIN).doc(`usuarios/${CLIENTE}`).get());
  });

  // El panel ofrece "eliminar" en la pestaña de Clientes, pero la regla de
  // delete sigue restringida a conductores del propio gremio. Se fija acá
  // para que quede explícito: ese botón falla sobre un cliente.
  test('un admin NO puede borrar a un cliente (el botón del panel falla)', async () => {
    await assertFails(como(env, ADMIN).doc(`usuarios/${CLIENTE}`).delete());
  });

  // CompleteProfileController.saveProfile
  test('el usuario actualiza su perfil sin cambiarse el rol', async () => {
    await assertSucceeds(
      como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).update({
        nombre: 'Kevin', telefono: '3001234567', rol: 'cliente',
      }),
    );
  });

  // Escalada de privilegios: la regla fija `rol` y `adminId`.
  test('un cliente NO puede promoverse a conductor', async () => {
    await assertFails(
      como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).update({ rol: 'conductor' }),
    );
  });

  test('un cliente NO puede asignarse un adminId', async () => {
    await assertFails(
      como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).update({ adminId: ADMIN }),
    );
  });

  // FcmService: persistir el token es la escritura más frecuente de la app.
  test('el usuario guarda su fcmToken', async () => {
    await assertSucceeds(
      como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).set(
        { fcmToken: 'tok-123', rol: 'cliente' }, { merge: true },
      ),
    );
  });

  // InicioConductorViewmodel.toggleConductorConnection
  test('el conductor alterna su disponibilidad', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).doc(`usuarios/${CONDUCTOR}`).set(
        { disponible: true, rol: 'conductor' }, { merge: true },
      ),
    );
  });

  test('un anónimo no lee perfiles', async () => {
    await assertFails(comoAnonimo(env).doc(`usuarios/${CLIENTE}`).get());
  });
});

describe('conductores_conectados — presencia', () => {
  // InicioConductorViewmodel.guardarUbicacionConectado (y el refresco cada 2 min)
  test('el conductor publica su propia posición', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).doc(`conductores_conectados/${CONDUCTOR}`).set({
        ubicacion: { lat: 8.24, lng: -73.35 },
      }),
    );
  });

  // A2: al aceptar, sale del índice de despacho borrando su presencia.
  test('el conductor borra su propia presencia al tomar un viaje', async () => {
    await sembrar(env, `conductores_conectados/${CONDUCTOR}`, { ubicacion: { lat: 8.2, lng: -73.3 } });
    await assertSucceeds(
      como(env, CONDUCTOR).doc(`conductores_conectados/${CONDUCTOR}`).delete(),
    );
  });

  test('nadie escribe la presencia de otro', async () => {
    await assertFails(
      como(env, CLIENTE).doc(`conductores_conectados/${CONDUCTOR}`).set({
        ubicacion: { lat: 0, lng: 0 },
      }),
    );
  });

  // El mapa "sonar" del cliente necesita leerlos a todos.
  test('un cliente autenticado lista los conductores conectados', async () => {
    await sembrar(env, `conductores_conectados/${CONDUCTOR}`, { ubicacion: { lat: 8.2, lng: -73.3 } });
    await assertSucceeds(como(env, CLIENTE).collection('conductores_conectados').get());
  });
});

describe('ubicaciones — direcciones guardadas', () => {
  beforeEach(async () => {
    await sembrar(env, 'ubicaciones/u1', { userId: CLIENTE, nombre: 'Casa' });
    await sembrar(env, 'ubicaciones/u2', { userId: OTRO_CLIENTE, nombre: 'Casa ajena' });
  });

  // C1: la query SIN filtro que tenía `getTodasUbicaciones` es exactamente
  // esto, y con las reglas endurecidas falla. Ese fallo era el que rompía el
  // autocompletado; con el ruleset abierto que hay en producción, en cambio,
  // devolvía las direcciones de TODOS los usuarios.
  test('la query sin filtrar por userId es rechazada', async () => {
    await assertFails(como(env, CLIENTE).collection('ubicaciones').get());
  });

  // La versión corregida de `getUbicacionesDeUsuario`.
  test('la query filtrada por el propio userId funciona', async () => {
    await assertSucceeds(
      como(env, CLIENTE).collection('ubicaciones').where('userId', '==', CLIENTE).limit(50).get(),
    );
  });

  test('no se pueden pedir las direcciones de otro usuario', async () => {
    await assertFails(
      como(env, CLIENTE).collection('ubicaciones').where('userId', '==', OTRO_CLIENTE).get(),
    );
  });

  test('se puede guardar una dirección propia', async () => {
    await assertSucceeds(
      como(env, CLIENTE).collection('ubicaciones').add({ userId: CLIENTE, nombre: 'Trabajo' }),
    );
  });

  test('no se puede guardar a nombre de otro', async () => {
    await assertFails(
      como(env, CLIENTE).collection('ubicaciones').add({ userId: OTRO_CLIENTE, nombre: 'x' }),
    );
  });
});

describe('usuarios/{uid}/favoritos', () => {
  test('el usuario gestiona sus favoritos', async () => {
    const db = como(env, CLIENTE);
    await assertSucceeds(db.collection(`usuarios/${CLIENTE}/favoritos`).add({ nombre: 'Casa' }));
    await assertSucceeds(db.collection(`usuarios/${CLIENTE}/favoritos`).get());
  });

  test('nadie ve los favoritos de otro', async () => {
    await assertFails(como(env, CLIENTE).collection(`usuarios/${OTRO_CLIENTE}/favoritos`).get());
  });
});

describe('soporte, reportes y emergencias', () => {
  test('el usuario abre su chat de soporte y escribe', async () => {
    const db = como(env, CLIENTE);
    await assertSucceeds(db.doc(`soporte_chats/${CLIENTE}`).set({ abierto: true }));
    await assertSucceeds(
      db.collection(`soporte_chats/${CLIENTE}/mensajes`).add({ texto: 'hola' }),
    );
  });

  test('otro usuario no lee ese chat', async () => {
    await sembrar(env, `soporte_chats/${CLIENTE}`, { abierto: true });
    await assertFails(como(env, OTRO_CLIENTE).doc(`soporte_chats/${CLIENTE}`).get());
  });

  test('el admin sí lo lee', async () => {
    await sembrar(env, `soporte_chats/${CLIENTE}`, { abierto: true });
    await assertSucceeds(como(env, ADMIN).doc(`soporte_chats/${CLIENTE}`).get());
  });

  test('el cliente crea un reporte a su nombre pero no puede leerlos', async () => {
    const db = como(env, CLIENTE);
    await assertSucceeds(db.collection('reportes').add({ clienteId: CLIENTE, motivo: 'x' }));
    await assertFails(db.collection('reportes').get());
  });

  test('el admin lee los reportes', async () => {
    await sembrar(env, 'reportes/r1', { clienteId: CLIENTE, motivo: 'x' });
    await assertSucceeds(como(env, ADMIN).collection('reportes').get());
  });

  // PanicButton
  test('el usuario dispara una emergencia a su nombre', async () => {
    await assertSucceeds(
      como(env, CLIENTE).collection('emergencias').add({ userId: CLIENTE, lat: 8.2, lng: -73.3 }),
    );
  });

  test('no se puede disparar una emergencia a nombre de otro', async () => {
    await assertFails(
      como(env, CLIENTE).collection('emergencias').add({ userId: OTRO_CLIENTE }),
    );
  });
});

describe('administradores', () => {
  // FcmService: solo escribe si el documento ya existe.
  test('el admin actualiza su propio documento (fcmToken)', async () => {
    await assertSucceeds(
      como(env, ADMIN).doc(`administradores/${ADMIN}`).set(
        { fcmToken: 'tok' }, { merge: true },
      ),
    );
  });

  // Escalada de privilegios: `isAdminRole()` solo comprueba que exista
  // `administradores/{uid}`, así que poder crearse el propio documento
  // equivale a auto-promoverse a administrador.
  test('un cliente NO puede crearse como admin', async () => {
    await assertFails(
      como(env, CLIENTE).doc(`administradores/${CLIENTE}`).set({ nombre: 'falso' }),
    );
  });

  test('un conductor tampoco puede', async () => {
    await assertFails(
      como(env, CONDUCTOR).doc(`administradores/${CONDUCTOR}`).set({ nombre: 'falso' }),
    );
  });

  test('un admin no puede borrarse (ni borrar a otro)', async () => {
    await assertFails(como(env, ADMIN).doc(`administradores/${ADMIN}`).delete());
  });

  // Limitación conocida y documentada en firestore.rules: la lectura está
  // abierta a cualquier autenticado porque `AdminFcmService.sendToAllAdmins`
  // lee la colección entera para juntar tokens. Se fija para que quede
  // visible que expone nombre/teléfono/gremio de los admins.
  test('cualquier autenticado lee la lista de admins (limitación aceptada)', async () => {
    await assertSucceeds(como(env, CLIENTE).collection('administradores').get());
  });

  test('un anónimo no la lee', async () => {
    await assertFails(comoAnonimo(env).collection('administradores').get());
  });
});
