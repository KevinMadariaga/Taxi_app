// Reglas de la colección `solicitudes` — el corazón del producto.
//
// Contexto: en producción está desplegado un ruleset abierto
// (`allow read, write: if true`); el `firestore.rules` de este repo es la
// versión endurecida que NO se ha desplegado. Estas pruebas existen para poder
// desplegarla sabiendo que no rompe ningún acceso legítimo de la app.
//
// Cada caso corresponde a una operación real del código, anotada con el sitio
// que la ejecuta.

import { test, describe, before, after, beforeEach } from 'node:test';
import {
  crearEntorno, sembrarActores, sembrar, como, comoAnonimo, solicitud,
  assertFails, assertSucceeds,
  CLIENTE, OTRO_CLIENTE, CONDUCTOR, OTRO_CONDUCTOR, ADMIN,
} from './helpers.js';

let env;
before(async () => { env = await crearEntorno(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarActores(env);
});

describe('solicitudes — crear', () => {
  // SolicitudRepositoryImpl.crear
  test('el cliente crea su propia solicitud en buscando', async () => {
    const db = como(env, CLIENTE);
    await assertSucceeds(db.collection('solicitudes').add(solicitud()));
  });

  test('no se puede crear a nombre de otro cliente', async () => {
    const db = como(env, CLIENTE);
    await assertFails(
      db.collection('solicitudes').add(solicitud({ clienteId: OTRO_CLIENTE })),
    );
  });

  test('no se puede crear ya asignada (saltarse el flujo)', async () => {
    const db = como(env, CLIENTE);
    await assertFails(
      db.collection('solicitudes').add(solicitud({ estado: 'asignado' })),
    );
  });

  test('un anónimo no puede crear', async () => {
    await assertFails(comoAnonimo(env).collection('solicitudes').add(solicitud()));
  });
});

describe('solicitudes — leer', () => {
  test('el dueño lee su solicitud', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertSucceeds(como(env, CLIENTE).doc('solicitudes/s1').get());
  });

  test('otro cliente NO puede leerla', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(como(env, OTRO_CLIENTE).doc('solicitudes/s1').get());
  });

  test('un anónimo NO puede leerla', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(comoAnonimo(env).doc('solicitudes/s1').get());
  });

  // PendingSolicitudesController.subscribe — el conductor necesita ver las
  // solicitudes abiertas ANTES de que sean suyas.
  test('un conductor lee una solicitud en buscando que no es suya', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertSucceeds(como(env, CONDUCTOR).doc('solicitudes/s1').get());
  });

  test('un conductor NO lee una solicitud ya asignada a otro', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'asignado', conductorId: OTRO_CONDUCTOR }));
    await assertFails(como(env, CONDUCTOR).doc('solicitudes/s1').get());
  });

  // InicioConductorViewmodel._subscribeAssignedToMe / pantalla de viaje.
  test('el conductor asignado lee su viaje', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'en camino', conductorId: CONDUCTOR }));
    await assertSucceeds(como(env, CONDUCTOR).doc('solicitudes/s1').get());
  });

  // La lista del conductor filtra por estado; la query debe pasar las reglas.
  test('la query de solicitudes en buscando funciona para un conductor', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await sembrar(env, 'solicitudes/s2', solicitud({ clienteId: OTRO_CLIENTE }));
    const db = como(env, CONDUCTOR);
    await assertSucceeds(
      db.collection('solicitudes')
        .where('estado', 'in', ['buscando', 'pending', 'pendiente'])
        .get(),
    );
  });

  test('un cliente NO puede listar todas las solicitudes', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ clienteId: OTRO_CLIENTE }));
    await assertFails(como(env, CLIENTE).collection('solicitudes').get());
  });
});

describe('solicitudes — actualizar', () => {
  // InicioConductorViewmodel.aceptarSolicitud
  test('un conductor acepta una solicitud en buscando', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertSucceeds(
      como(env, CONDUCTOR).doc('solicitudes/s1').update({
        estado: 'asignado',
        conductor: { id: CONDUCTOR },
      }),
    );
  });

  // InicioConductorViewmodel.enviarContraoferta
  test('un conductor envía contraoferta sobre una solicitud en buscando', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertSucceeds(
      como(env, CONDUCTOR).doc('solicitudes/s1').set(
        { contraofertas: { [CONDUCTOR]: { valor: 15000, estado: 'pendiente_cliente' } } },
        { merge: true },
      ),
    );
  });

  // El bug C3: un conductor NO asignado tocando un viaje ajeno ya en curso.
  test('un conductor ajeno NO puede tocar un viaje en curso de otro', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'en camino', conductorId: OTRO_CONDUCTOR }));
    await assertFails(
      como(env, CONDUCTOR).doc('solicitudes/s1').update({ conductor: { id: CONDUCTOR } }),
    );
  });

  // BuscandoTaxiViewModel.aceptarContraofertaDeConductor / cancelar / actualizar valor
  test('el dueño acepta una contraoferta', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertSucceeds(
      como(env, CLIENTE).doc('solicitudes/s1').update({
        estado: 'asignado',
        conductor: { id: CONDUCTOR },
      }),
    );
  });

  test('otro cliente NO puede modificarla', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(
      como(env, OTRO_CLIENTE).doc('solicitudes/s1').update({ estado: 'cancelado' }),
    );
  });

  // ViajeConductorViewModel: reportar llegada, comenzar ruta, finalizar, cancelar.
  test('el conductor asignado avanza el estado del viaje', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'asignado', conductorId: CONDUCTOR }));
    const db = como(env, CONDUCTOR);
    await assertSucceeds(db.doc('solicitudes/s1').update({ estado: 'en espera' }));
    await assertSucceeds(db.doc('solicitudes/s1').update({ estado: 'en ruta' }));
    await assertSucceeds(db.doc('solicitudes/s1').update({ estado: 'completado' }));
  });

  // A3: cancelación desde el lado del conductor.
  test('el conductor asignado cancela su viaje', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'asignado', conductorId: CONDUCTOR }));
    await assertSucceeds(
      como(env, CONDUCTOR).doc('solicitudes/s1').update({
        estado: 'cancelado',
        cancelledBy: 'conductor',
      }),
    );
  });

  test('un anónimo NO puede modificar nada', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(comoAnonimo(env).doc('solicitudes/s1').update({ estado: 'cancelado' }));
  });
});

describe('solicitudes — borrar', () => {
  // Las reglas prohíben borrar a TODOS. El código lo intenta igual
  // (BuscandoTaxiViewModel._borrarSolicitudTrasGracia) y se traga el fallo:
  // este test fija que el borrado del cliente no funciona, para que quede
  // explícito que esos documentos se acumulan.
  test('ni el dueño puede borrar', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(como(env, CLIENTE).doc('solicitudes/s1').delete());
  });

  test('ni un admin puede borrar', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(como(env, ADMIN).doc('solicitudes/s1').delete());
  });
});

describe('solicitudes/{id}/mensajes — chat del viaje', () => {
  beforeEach(async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'en ruta', conductorId: CONDUCTOR }));
  });

  test('el cliente escribe en el chat de su viaje', async () => {
    await assertSucceeds(
      como(env, CLIENTE).collection('solicitudes/s1/mensajes').add({
        senderId: CLIENTE, texto: 'Ya salgo',
      }),
    );
  });

  test('el conductor asignado escribe en el chat', async () => {
    await assertSucceeds(
      como(env, CONDUCTOR).collection('solicitudes/s1/mensajes').add({
        senderId: CONDUCTOR, texto: 'En camino',
      }),
    );
  });

  test('no se puede escribir suplantando a otro', async () => {
    await assertFails(
      como(env, CLIENTE).collection('solicitudes/s1/mensajes').add({
        senderId: CONDUCTOR, texto: 'suplantado',
      }),
    );
  });

  test('un tercero no participa del chat', async () => {
    await assertFails(
      como(env, OTRO_CONDUCTOR).collection('solicitudes/s1/mensajes').get(),
    );
  });

  test('el contenido del mensaje es inmutable y no se puede borrar', async () => {
    await sembrar(env, 'solicitudes/s1/mensajes/m1', { senderId: CLIENTE, texto: 'hola' });
    await assertFails(
      como(env, CLIENTE).doc('solicitudes/s1/mensajes/m1').update({ texto: 'editado' }),
    );
    await assertFails(
      como(env, CONDUCTOR).doc('solicitudes/s1/mensajes/m1').update({ senderId: CONDUCTOR }),
    );
    await assertFails(como(env, CLIENTE).doc('solicitudes/s1/mensajes/m1').delete());
  });

  // `ChatFirestoreDatasource.markMessageRead` hace `update({'readBy.$uid': true})`.
  // Con la regla original (`allow update: if false`) el mensaje se enviaba y se
  // leía bien pero NUNCA se marcaba como leído: el contador de no leídos no
  // bajaba nunca. Detectado en dispositivo real con un permission-denied por
  // cada mensaje abierto.
  describe('acuse de lectura (readBy)', () => {
    beforeEach(async () => {
      await sembrar(env, 'solicitudes/s1/mensajes/m1', {
        senderId: CLIENTE, texto: 'hola', readBy: { [CLIENTE]: true },
      });
    });

    test('el destinatario marca el mensaje como leído', async () => {
      await assertSucceeds(
        como(env, CONDUCTOR).doc('solicitudes/s1/mensajes/m1')
          .update({ [`readBy.${CONDUCTOR}`]: true }),
      );
    });

    test('nadie puede marcar como leído en nombre de otro', async () => {
      await assertFails(
        como(env, CONDUCTOR).doc('solicitudes/s1/mensajes/m1')
          .update({ [`readBy.${CLIENTE}`]: false }),
      );
      await assertFails(
        como(env, CLIENTE).doc('solicitudes/s1/mensajes/m1')
          .update({ [`readBy.${CONDUCTOR}`]: true }),
      );
    });

    test('el acuse no sirve para colar cambios en el mensaje', async () => {
      await assertFails(
        como(env, CONDUCTOR).doc('solicitudes/s1/mensajes/m1').update({
          [`readBy.${CONDUCTOR}`]: true,
          texto: 'editado de contrabando',
        }),
      );
    });

    test('un tercero no puede marcar nada', async () => {
      await assertFails(
        como(env, OTRO_CONDUCTOR).doc('solicitudes/s1/mensajes/m1')
          .update({ [`readBy.${OTRO_CONDUCTOR}`]: true }),
      );
    });

    test('funciona también sobre un mensaje que aún no tiene readBy', async () => {
      await sembrar(env, 'solicitudes/s1/mensajes/m2', {
        senderId: CONDUCTOR, texto: 'sin readBy',
      });
      await assertSucceeds(
        como(env, CLIENTE).doc('solicitudes/s1/mensajes/m2')
          .update({ [`readBy.${CLIENTE}`]: true }),
      );
    });
  });
});
