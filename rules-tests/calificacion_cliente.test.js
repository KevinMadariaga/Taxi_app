// Calificación que el CONDUCTOR le da al cliente al terminar el viaje
// (`ResumenViajeFirebaseService.guardarCalificacionAlCliente`) y lectura del
// promedio agregado en `calificaciones_clientes/{uid}`.

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
});

const calificar = (puntaje = 4) => ({
  calificacionCliente: puntaje,
  comentarioCalificacionCliente: 'Puntual',
  fechaCalificacionCliente: new Date(),
});

describe('solicitudes — el conductor califica al cliente', () => {
  test('el conductor asignado califica un viaje completado', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    await assertSucceeds(como(env, CONDUCTOR).doc('solicitudes/s1').update(calificar()));
  });

  test('otro conductor no puede calificar un viaje que no fue suyo', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    await assertFails(como(env, OTRO_CONDUCTOR).doc('solicitudes/s1').update(calificar()));
  });

  test('el cliente no puede ponerse su propia calificación', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    await assertFails(como(env, CLIENTE).doc('solicitudes/s1').update(calificar(5)));
  });

  test('no se califica un viaje en curso ni uno cancelado', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'en ruta', conductorId: CONDUCTOR }));
    await assertFails(como(env, CONDUCTOR).doc('solicitudes/s1').update(calificar()));
    await sembrar(env, 'solicitudes/s2', solicitud({ estado: 'cancelado', conductorId: CONDUCTOR }));
    await assertFails(como(env, CONDUCTOR).doc('solicitudes/s2').update(calificar()));
  });

  test('una cuenta conductor no la cuela sobre una solicitud en buscando', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud());
    await assertFails(como(env, OTRO_CONDUCTOR).doc('solicitudes/s1').update(calificar(1)));
  });

  test('una calificación ya puesta no se reescribe', async () => {
    await sembrar(env, 'solicitudes/s1', {
      ...solicitud({ estado: 'completado', conductorId: CONDUCTOR }),
      calificacionCliente: 5,
    });
    await assertFails(como(env, CONDUCTOR).doc('solicitudes/s1').update(calificar(1)));
  });

  test('puntaje fuera de 1–5 o no numérico se rechaza', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    const db = como(env, CONDUCTOR).doc('solicitudes/s1');
    await assertFails(db.update(calificar(0)));
    await assertFails(db.update(calificar(6)));
    await assertFails(db.update(calificar('5')));
  });

  test('calificar no sirve para colar otros campos', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    await assertFails(
      como(env, CONDUCTOR).doc('solicitudes/s1').update({ ...calificar(), 'tarifa.total': 0 }),
    );
  });

  test('la calificación del cliente al conductor sigue funcionando', async () => {
    await sembrar(env, 'solicitudes/s1', solicitud({ estado: 'completado', conductorId: CONDUCTOR }));
    await assertSucceeds(
      como(env, CLIENTE).doc('solicitudes/s1').update({ calificacion: 5 }),
    );
  });
});

describe('calificaciones_clientes — promedio agregado', () => {
  beforeEach(async () => {
    await sembrar(env, `calificaciones_clientes/${CLIENTE}`, { promedio: 4.5, total: 2 });
  });

  test('el cliente lee su propio promedio', async () => {
    await assertSucceeds(como(env, CLIENTE).doc(`calificaciones_clientes/${CLIENTE}`).get());
  });

  test('un conductor lee el promedio de un cliente', async () => {
    await assertSucceeds(como(env, OTRO_CONDUCTOR).doc(`calificaciones_clientes/${CLIENTE}`).get());
  });

  test('un admin lo lee', async () => {
    await assertSucceeds(como(env, ADMIN).doc(`calificaciones_clientes/${CLIENTE}`).get());
  });

  test('otro cliente no lo lee', async () => {
    await assertFails(como(env, OTRO_CLIENTE).doc(`calificaciones_clientes/${CLIENTE}`).get());
  });

  test('nadie lo escribe desde la app, ni el propio cliente', async () => {
    await assertFails(
      como(env, CLIENTE).doc(`calificaciones_clientes/${CLIENTE}`).set({ promedio: 5, total: 99 }),
    );
    await assertFails(
      como(env, CONDUCTOR).doc(`calificaciones_clientes/${CLIENTE}`).set({ promedio: 1, total: 1 }),
    );
  });
});
