// Reglas de `storage.rules` — auditoría de seguridad: antes NO EXISTÍA este
// archivo (ni un bloque `storage` en firebase.json), así que lo que regía en
// producción era lo que hubiera quedado en la consola de Firebase, sin
// versionar ni testear. Estas pruebas ejercitan la regla endurecida contra
// el emulador de Storage, igual que `solicitudes.test.js` hace con Firestore.
//
// Requiere el emulador de Storage (`firebase emulators:exec --only storage`,
// ver el script "test" de package.json).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { test, describe, before, after } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

const aqui = dirname(fileURLToPath(import.meta.url));
const REGLAS = join(aqui, '..', 'storage.rules');

const DUENO = 'usuario-1';
const OTRO = 'usuario-2';

// 4 bytes válidos de PNG (firma mínima) — el contenido no importa para las
// reglas, solo `contentType`/`size`, pero un buffer no vacío es más realista
// que subir 0 bytes.
const IMG = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-taxi-rules',
    storage: {
      rules: readFileSync(REGLAS, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});
after(async () => { await env.cleanup(); });

const como = (uid) => env.authenticatedContext(uid).storage();
const comoAnonimo = () => env.unauthenticatedContext().storage();

describe('usuarios/{uid}/... — foto de perfil y de vehículo', () => {
  test('el dueño sube su propia foto (image/webp)', async () => {
    await assertSucceeds(
      como(DUENO).ref(`usuarios/${DUENO}/profile_1.webp`)
        .put(IMG, { contentType: 'image/webp' }),
    );
  });

  test('nadie puede escribir en la carpeta de otro usuario', async () => {
    await assertFails(
      como(OTRO).ref(`usuarios/${DUENO}/profile_1.webp`)
        .put(IMG, { contentType: 'image/webp' }),
    );
  });

  test('un anónimo no puede subir nada', async () => {
    await assertFails(
      comoAnonimo().ref(`usuarios/${DUENO}/profile_1.webp`)
        .put(IMG, { contentType: 'image/webp' }),
    );
  });

  // Antes de esta regla, cualquier archivo (PDF, APK, lo que sea) podía
  // subirse a la carpeta de fotos.
  test('no se puede subir un archivo que no sea imagen', async () => {
    await assertFails(
      como(DUENO).ref(`usuarios/${DUENO}/profile_1.webp`)
        .put(IMG, { contentType: 'application/pdf' }),
    );
  });

  test('no se puede subir un archivo mayor a 5 MB', async () => {
    const grande = Buffer.alloc(5 * 1024 * 1024 + 1, 1);
    await assertFails(
      como(DUENO).ref(`usuarios/${DUENO}/profile_1.webp`)
        .put(grande, { contentType: 'image/webp' }),
    );
  });

  test('cualquier autenticado LEE la foto de cualquiera (se muestra entre roles)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.storage().ref(`usuarios/${DUENO}/profile_1.webp`).put(IMG);
    });
    await assertSucceeds(
      como(OTRO).ref(`usuarios/${DUENO}/profile_1.webp`).getDownloadURL(),
    );
  });

  test('un anónimo no lee nada', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.storage().ref(`usuarios/${DUENO}/profile_1.webp`).put(IMG);
    });
    await assertFails(
      comoAnonimo().ref(`usuarios/${DUENO}/profile_1.webp`).getDownloadURL(),
    );
  });

  test('el dueño borra su propia foto; otro usuario no puede', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.storage().ref(`usuarios/${DUENO}/profile_1.webp`).put(IMG);
    });
    await assertFails(como(OTRO).ref(`usuarios/${DUENO}/profile_1.webp`).delete());
    await assertSucceeds(como(DUENO).ref(`usuarios/${DUENO}/profile_1.webp`).delete());
  });
});

describe('cualquier otra ruta', () => {
  test('denegada por defecto', async () => {
    await assertFails(
      como(DUENO).ref('otra_carpeta/archivo.webp')
        .put(IMG, { contentType: 'image/webp' }),
    );
  });
});
