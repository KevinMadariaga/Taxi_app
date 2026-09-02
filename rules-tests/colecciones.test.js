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

  // FLUJO PRINCIPAL DEL PANEL: el admin aprueba la membresía de un usuario
  // que TODAVÍA es `rol: 'cliente'` con `solicitudConductor: true`. La regla
  // original exigía `rol == 'conductor'` y un `adminId` que ningún documento
  // tiene, así que bloqueaba justo esta operación.
  test('el admin aprueba la membresía de un cliente que pidió ser conductor', async () => {
    await sembrar(env, `usuarios/${OTRO_CLIENTE}`, {
      rol: 'cliente', solicitudConductor: true, nombre: 'Aspirante',
    });
    await assertSucceeds(
      como(env, ADMIN).doc(`usuarios/${OTRO_CLIENTE}`).set({
        membresia: 'activa',
        membresiaDias: 30,
        servicioActivo: true,
        solicitudConductor: false,
      }, { merge: true }),
    );
  });

  test('el admin revoca la membresía de un conductor', async () => {
    await assertSucceeds(
      como(env, ADMIN).doc(`usuarios/${CONDUCTOR}`).set(
        { membresia: '', servicioActivo: false }, { merge: true },
      ),
    );
  });

  test('el admin promueve a un cliente a conductor', async () => {
    await assertSucceeds(
      como(env, ADMIN).doc(`usuarios/${CLIENTE}`).set({ rol: 'conductor' }, { merge: true }),
    );
  });

  // El panel ofrece eliminar en ambas pestañas.
  test('el admin elimina a un cliente y a un conductor', async () => {
    await assertSucceeds(como(env, ADMIN).doc(`usuarios/${CLIENTE}`).delete());
    await assertSucceeds(como(env, ADMIN).doc(`usuarios/${CONDUCTOR}`).delete());
  });

  test('un no-admin no puede eliminar a otro usuario', async () => {
    await assertFails(como(env, CLIENTE).doc(`usuarios/${OTRO_CLIENTE}`).delete());
  });

  // EliminarCuentaScreen (botón "Eliminar cuenta" en Configuración de la
  // app, cliente y conductor): el usuario borra su propio doc.
  test('un usuario elimina su propia cuenta', async () => {
    await assertSucceeds(como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).delete());
    await assertSucceeds(como(env, CONDUCTOR).doc(`usuarios/${CONDUCTOR}`).delete());
  });

  // CompleteProfileController.saveProfile
  test('el usuario actualiza su perfil sin cambiarse el rol', async () => {
    await assertSucceeds(
      como(env, CLIENTE).doc(`usuarios/${CLIENTE}`).update({
        nombre: 'Kevin', telefono: '3001234567', rol: 'cliente',
      }),
    );
  });

  // Cambiar el propio `rol` es un flujo real de la app, no una escalada:
  // "Modo conductor" (perfil.dart:331), "Volver a ser cliente" (:370,
  // InicioConductorView:1598) y el auto-registro de conductor
  // (completar_registro_conductor_view.dart:171). Prohibirlo dejaba al
  // usuario en el home del conductor con `rol: 'cliente'` en Firestore y la
  // lista de solicitudes vacía para siempre (visto en dispositivo real).
  test('el usuario cambia su propio rol a conductor y vuelve a cliente', async () => {
    const db = como(env, CLIENTE);
    // perfil.dart:331 -> UserDataService.cambiarRolAConductor
    await assertSucceeds(
      db.doc(`usuarios/${CLIENTE}`).set(
        { rol: 'conductor' }, { merge: true },
      ),
    );
    // completar_registro_conductor_view.dart:171 -> guardarSolicitudConductor
    await assertSucceeds(
      db.doc(`usuarios/${CLIENTE}`).set(
        { rol: 'conductor', solicitudConductor: true, placa: 'ABC123' },
        { merge: true },
      ),
    );
    // perfil.dart:370 -> UserDataService.volverACliente
    await assertSucceeds(
      db.doc(`usuarios/${CLIENTE}`).set(
        { rol: 'cliente', solicitudConductor: false }, { merge: true },
      ),
    );
  });

  // La guarda real: la membresía es lo que habilita tomar viajes
  // (`aceptarSolicitud` la valida en su transacción) y solo la otorga el
  // admin. Auto-marcarse conductor sirve para ver la lista, no para trabajar.
  test('un usuario NO puede darse membresía a sí mismo', async () => {
    const db = como(env, CLIENTE);
    await assertFails(
      db.doc(`usuarios/${CLIENTE}`).set({ membresia: 'activa' }, { merge: true }),
    );
    await assertFails(
      db.doc(`usuarios/${CLIENTE}`).update({
        membresiaVence: new Date('2030-01-01'),
      }),
    );
    // Ni siquiera acompañada de un cambio de rol permitido.
    await assertFails(
      db.doc(`usuarios/${CLIENTE}`).set(
        { rol: 'conductor', membresia: 'activa' }, { merge: true },
      ),
    );
  });

  test('un conductor con membresía no puede extendérsela ni revocársela', async () => {
    await sembrar(env, `usuarios/${CONDUCTOR}`, {
      rol: 'conductor', membresia: 'activa',
      membresiaVence: new Date('2026-09-01'),
    });
    const db = como(env, CONDUCTOR);
    await assertFails(
      db.doc(`usuarios/${CONDUCTOR}`).update({
        membresiaVence: new Date('2031-01-01'),
      }),
    );
    // Pero sí puede seguir editando el resto de su perfil.
    await assertSucceeds(
      db.doc(`usuarios/${CONDUCTOR}`).update({ nombre: 'Kevin', disponible: true }),
    );
  });

  // `initial_screen_resolver.dart:137` abre el panel de admin con
  // `usuarios.rol == 'admin' || 'administrador'`, así que el rol propio está
  // acotado a los dos valores que el usuario puede alternar.
  test('un usuario NO puede escribirse un rol de admin', async () => {
    const db = como(env, CLIENTE);
    await assertFails(db.doc(`usuarios/${CLIENTE}`).update({ rol: 'administrador' }));
    await assertFails(db.doc(`usuarios/${CLIENTE}`).update({ rol: 'admin' }));
  });

  test('el admin sí otorga y revoca membresía', async () => {
    const db = como(env, ADMIN);
    await assertSucceeds(
      db.doc(`usuarios/${CLIENTE}`).set({
        rol: 'conductor', membresia: 'activa',
        membresiaVence: new Date('2026-12-01'),
      }, { merge: true }),
    );
    await assertSucceeds(
      db.doc(`usuarios/${CLIENTE}`).set({ membresia: '' }, { merge: true }),
    );
  });

  // `adminId` (modelo de gremios) quedó sin uso: ningún documento lo tiene y
  // nada filtra por él, así que las reglas ya no lo miran. Esta prueba fija
  // que, por eso mismo, escribírselo NO otorga ningún privilegio — quien lo
  // haga sigue sin poder leer usuarios ajenos ni actuar como admin.
  test('asignarse un adminId no da privilegios de admin', async () => {
    const db = como(env, CLIENTE);
    await db.doc(`usuarios/${CLIENTE}`).update({ adminId: ADMIN });
    await assertFails(db.doc(`usuarios/${OTRO_CLIENTE}`).get());
    await assertFails(db.collection('usuarios').get());
    await assertFails(db.doc(`usuarios/${CONDUCTOR}`).update({ membresia: 'activa' }));
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
