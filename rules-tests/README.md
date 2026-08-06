# Pruebas de `firestore.rules`

Ejercitan las reglas de seguridad contra el emulador de Firestore, sin tocar
producción y sin credenciales reales.

## Por qué existen

En producción hay desplegado un ruleset **abierto**:

```
match /{document=**} { allow read, write: if true; }
```

El `firestore.rules` de este repo es la versión endurecida, que **nunca se
desplegó**. Estas pruebas existen para poder desplegarla con la confianza de
que no rompe ningún acceso legítimo de la app — cada caso corresponde a una
operación real del código y está anotado con el sitio que la ejecuta.

Ya encontraron una escalada de privilegios: la regla de `administradores`
permitía `write` sobre el documento propio, y como `isAdminRole()` solo
comprueba que `administradores/{uid}` exista, cualquier usuario autenticado
podía auto-promoverse a administrador.

## Correr

```bash
cd rules-tests
npm install     # solo la primera vez
npm test
```

Necesita Java (lo pide el emulador de Firestore) y el CLI de Firebase. No
requiere estar logueado ni tener acceso al proyecto real: usa el projectId
ficticio `demo-taxi-rules`.

## Antes de desplegar las reglas

```bash
cd rules-tests && npm test        # tiene que dar 61/61
cd .. && firebase deploy --only firestore:rules
```

Tras desplegar, vigilar `permission-denied` en Crashlytics durante unas horas:
si alguna ruta de acceso quedó sin cubrir acá, aparecerá ahí (los errores async
ya se reportan correctamente desde el fix de observabilidad).

## Notas

- Los tests corren con `--test-concurrency=1` **a propósito**. `node --test`
  paraleliza por archivo, y como cada uno hace `clearFirestore()` en su
  `beforeEach`, en paralelo se borran los datos entre sí y aparecen fallos
  fantasma que no son de las reglas.
- `helpers.js` siembra con `withSecurityRulesDisabled`: montar el escenario no
  es parte de lo que se prueba.
