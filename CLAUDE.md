# CLAUDE.md — Taxi Ya

## Descripción del proyecto

**Taxi Ya** (`taxi_app`) es una aplicación móvil Flutter de transporte tipo taxi con geolocalización en tiempo real. Permite a clientes solicitar viajes, a conductores recibirlos y gestionarlos, y a administradores gestionar conductores dentro de un gremio. El backend es 100 % Firebase (Firestore, Auth, Storage, FCM, Crashlytics, Analytics, Remote Config, App Check).

- Versión: `1.0.1+24`
- SDK Flutter requerido: `^3.10.7`
- Plataformas objetivo: Android e iOS (también compilable en web/linux/windows pero no es el foco)

---

## Roles de usuario

| Rol | Descripción |
|---|---|
| **Cliente** | Se registra con Google, Apple u OTP teléfono. Solicita viajes, hace seguimiento en tiempo real y califica al conductor. |
| **Conductor** | Se registra con correo/contraseña gestionado por un administrador. Recibe solicitudes, puede aceptarlas o ignorarlas, y comparte su ubicación en tiempo real. |
| **Administrador** | Gestiona conductores de un gremio. Aprueba/rechaza registros de conductores. |

---

## Arquitectura

El proyecto usa una **arquitectura híbrida MVVM** en transición progresiva hacia módulos por feature:

```
View → ViewModel/Controller → UseCase/Repository/Service → Firebase → notifyListeners → View
```

### Capas activas

- **`core/`** — Infraestructura transversal: constantes, tema, auth adapter, servicios (FCM, tracking, notificaciones, remote config, ubicación).
- **`domain/`** — Entidades, contratos de repositorio (`ClientAuthRepository`, `AuthRepository`) y casos de uso.
- **`data/`** — Implementaciones concretas de repositorios y datasources (Firebase).
- **`presentation/`** — Pantallas nuevas: splash, login, complete profile. ViewModels con Provider.
- **`caracteristicas/`** — Patrón oficial (ver más abajo). Incluye **las dos pantallas
  de viaje activo**, que son las vivas:
  - `viaje_conductor/` — `ViajeConductorScreen`: el viaje completo del conductor,
    `asignado → completado`.
  - `viaje_cliente/` — `ViajeClienteScreen`: seguimiento del viaje del lado del cliente.
  - `confirmar_solicitud/`, `seleccion_destino/`, `autenticacion/`, `viaje_compartido/`,
    `verificacion_recogida/`.
- **`features/`** — Módulos autocontenidos:
  - `phone_auth/` — Auth por teléfono OTP, registro de conductor, registro de admin, panel de admin.
  - `resumen_viaje/` — Pantalla de resumen post-viaje con calificación.
  - `admin/` — Panel de administrador.
  - `client/` — Data legacy de cliente.
  - `trip_tracking_cliente/` y `driver_trip/` — **ya NO contienen pantallas.** Sus
    views/controllers/viewmodels se eliminaron por código muerto; solo quedan
    widgets, modelos y servicios que `caracteristicas/viaje_*` sigue usando
    (`trip_details_sheet`, `panic_button_fab`, `waiting_driver_modal`,
    `driver_waiting_client_modal`, `map_service`, `local_cache_service`,
    `trip_route_math_service`, `solicitud_model`, `usuario_model`…).
    No agregar pantallas nuevas ahí.
- **`screens/`** — Flujos legacy aún productivos: `usuario_cliente/` y `usuario_conductor/`
  (home del cliente, home del conductor, perfil, historial). Las pantallas de ruta
  (`RutaDestinoView`, `RutaClienteDestinoView`) se eliminaron: las reemplazan
  `caracteristicas/viaje_conductor/` y `caracteristicas/viaje_cliente/`.
- **`widgets/`** — Componentes UI reutilizables globales.
- **`helper/`** — Firebase init, permisos, sesión, mapas.
- **`routes/`** — `AppRoutes` con `onGenerateRoute`.

### Gestión de estado

`Provider` + `ChangeNotifier`. Los ViewModels son `ChangeNotifier`. Los usecases se proveen globalmente en `main.dart` mediante `MultiProvider`.

---

## Patrón arquitectónico oficial

Todo código **nuevo** debe seguir el patrón de `caracteristicas/` (ver `caracteristicas/autenticacion/` como referencia — ejemplo concreto: `dominio/repositorios/client_auth_repository.dart` es la interfaz abstracta, `datos/repositorios/client_auth_repository_impl.dart` es su implementación separada, y `dominio/casos_uso/sign_in_google_client_usecase.dart` es un caso de uso que depende solo de la interfaz):

- Capas separadas de datos/dominio/presentación.
- Repositorios abstractos con implementación inyectada (nunca una clase concreta usada directo como si fuera el contrato).
- ViewModels sin lógica de negocio — excepto ifs simples de UI, lógica de animación propia del widget, lógica de layout por tamaño/orientación, y routing simple.
- Modelos inmutables.

`features/` es el árbol donde vive hoy la mayoría del código funcional en producción, pero **no** es el patrón a replicar en código nuevo — su arquitectura interna es inconsistente entre módulos (algunos sin repository abstracto, algunos sin ViewModel).

Esta es una regla para desarrollo futuro; no implica una migración ni refactorización obligatoria del código existente en `features/` en este momento.

`presentation/` es el shell de arranque de la app (splash + update gate), no una arquitectura alternativa.

---

## Flujo de la solicitud (estados)

```
buscando → asignado → en espera → en camino → en ruta → completado
                                                       ↘ cancelado
                                                       ↘ sin respuesta
```

Implementado en `lib/core/constants/solicitud_estado.dart`. La clase `SolicitudEstado` centraliza normalización y clasificación de estados (terminal vs. activo).

---

## Colecciones Firestore principales

| Colección | Descripción |
|---|---|
| `solicitudes` | Documentos de viaje. Campos clave: `estado`, `cliente{}`, `conductor{}`, `tarifa{}`, `destino{}`, `updatedAt`. |
| `usuarios` | Perfil de **cliente, conductor Y admin** (comparten colección, doc id = uid, campo `rol`/`tipoUsuario` los distingue: `'cliente'`, `'conductor'`, `'admin'`/`'administrador'`): `nombre`, `apellido`, `placa`, `foto`/`fotoUrl`, `fotoVehiculo`, `telefono`, `rol`, `isProfileComplete`, `membresia`/`membresiaVence` (conductor), `deshabilitado` (cuenta deshabilitada por un admin). |
| `conductores_conectados` | Presencia en vivo del conductor conectado (doc id = uid): `ubicacion{lat,lng}`, `updatedAt`. Es lo que usa el reparto de solicitudes y el mapa "sonar" del cliente — **no** `conductores`. |
| `administradores` | **Ya NO determina quién es admin** (ver más abajo) — colección legacy que solo guarda datos de perfil opcionales (`nombre`, `telefono`, `foto`, `gremio`) y el token FCM para el broadcast de `AdminFcmService.sendToAllAdmins`. Un doc puede no existir para un admin real. |

`conductores` (sin guion bajo) **existe pero NO es el perfil del conductor**: son reglas de solo lectura (`firestore.rules`, `allow write: if false`) y aparece una sola vez en todo el código como fallback legacy de lectura. Antes esta tabla decía lo contrario — verificado y corregido en la auditoría de tracking/nombre de conductor (ver más abajo).

---

## Autenticación

- **Clientes**: Google Sign-In, Apple Sign-In, OTP por teléfono (Firebase Phone Auth).
- **Conductores**: correo + contraseña (gestionado por admin, no auto-registro).
- **Administradores**: sin flujo de registro en la app — se otorga a mano en Firestore console.

Punto de entrada de auth: `lib/core/auth/app_auth_adapter.dart` implementa `ClientAuthRepository`.

### Cómo se decide el rol (cliente / conductor / admin)

Los tres roles se leen del **mismo campo**: `usuarios/{uid}.rol` (o `role`; `tipoUsuario` es fallback legacy solo para conductor/cliente). No hay una colección aparte que determine quién es admin — decisión explícita para que el valor que se ve en Firestore console sea literalmente el que decide la pantalla, sin dos fuentes que puedan desalinearse (ver hallazgo del 2026-09-02 más abajo).

- `firestore.rules` → `isAdminRole()` lee `usuarios/{request.auth.uid}.rol in ['admin','administrador']`.
- `lib/core/services/initial_screen_resolver.dart` (cold-start) y `lib/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart` (login interactivo) enrutan con la misma lectura.

**Para dar de alta un admin**: en Firestore console, editar `usuarios/{uid}.rol` a `'admin'` (o `'administrador'`) para esa cuenta. No hace falta crear ningún otro documento — la colección `administradores` es legacy (ver tabla de colecciones) y no se lee para esto.

**Por qué no puede ser una auto-elevación**: `usuarios/{uid}` permite `create`/`update` propios, pero ambas reglas exigen `rol in ['cliente','conductor']` cuando el que escribe es el dueño del doc — un usuario nunca puede ponerse `rol: 'admin'` a sí mismo, ni al registrarse ni después. Solo otro admin (bypass de `isAdminRole()` en esas mismas reglas) o una edición directa en consola pueden otorgarlo. Cubierto por `rules-tests/colecciones.test.js` ("un usuario nuevo NO puede autodeclararse admin al registrarse").

**Consecuencia aceptada**: `AdminFcmService.sendToAllAdmins` (push a todos los admins) sigue leyendo tokens de la colección `administradores`, no de `usuarios` — un admin dado de alta solo por `rol` no recibe esas notificaciones push salvo que además tenga (o se le cree) un doc en `administradores/{uid}` con `fcmToken`. `FcmService` lo sincroniza solo si ese doc ya existe. No bloquea el acceso al panel, solo esa notificación específica.

---

## Servicios clave

| Servicio | Archivo | Propósito |
|---|---|---|
| `FcmService` | `core/services/fcm_service.dart` | Push notifications, token FCM en Firestore, handlers foreground/background/terminated. |
| `TrackingService` | `core/services/tracking_service.dart` | Actualización GPS del conductor en Firestore. |
| `BackgroundTrackingService` | `core/services/background_tracking_service.dart` | Tracking GPS en segundo plano (flutter_background_service). |
| `NotificacionesServicio` | `core/services/notificacion_servicio.dart` | Notificaciones locales. |
| `MapServiceAdapter` | `core/services/map_service_adapter.dart` | Cálculo de rutas y polilíneas (Google Maps). |
| `RouteCacheService` | `core/services/route_cache_service.dart` | Caché local de rutas calculadas. |

---

## Modelos principales

- `ClientUserModel` — cliente (Firestore ↔ dominio).
- `DriverModel` — conductor.
- `AdminModel` — administrador.
- `SolicitudModel` — documento de solicitud con `UsuarioModel` para cliente y conductor.
- `ResumenViajeModel` — datos post-viaje (calificación, tarifa, fechas).

---

## Comandos frecuentes

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en modo debug (mapa estático del home de cliente necesita la key,
# ver env.json.example más abajo)
flutter run --dart-define-from-file=env.json

# QA de OTP telefónico con números ficticios (solo no-release)
flutter run --dart-define=PHONE_AUTH_TEST_MODE=true

# Tests
flutter test

# Build Android (Google Play) — el flag es obligatorio: sin él, el bundle
# queda con STATIC_MAPS_API_KEY vacía compilada adentro para siempre en esa
# versión (no se puede corregir sin subir una versión nueva).
flutter build appbundle --release --dart-define-from-file=env.json

# Build iOS (App Store) — mismo flag
flutter build ios --release --dart-define-from-file=env.json
```

**`env.json`** (no trackeado en git, copiar de `env.json.example`): contiene `STATIC_MAPS_API_KEY`, la key de Google Static Maps API usada por el mapa estático del home de cliente (`InicioClienteView`). Es una key HTTP distinta de la nativa de Android/iOS (esa está restringida por package/bundle id y no sirve para peticiones HTTP planas desde Dart) — necesita "Maps Static API" habilitada en Cloud Console y sin restricción de aplicación Android/iOS. VS Code: usar la config "taxi_app" en `.vscode/launch.json` (ya incluye el flag).

**Para no tener que escribir `--dart-define-from-file=env.json` cada vez** (el flag es fácil de olvidar y sin él el mapa estático cae al placeholder):
- **VS Code**: `.vscode/launch.json` ya trae el flag — correr con F5/Run usando la config "taxi_app" en vez de un `flutter run` suelto en la terminal integrada.
- **Terminal**: usar el `Makefile` de la raíz — `make run` (equivale a `flutter run` con el flag), `make run-release`, `make build-android`, `make build-ios`.

---

## Análisis de grafo del código (Graphify)

El proyecto tiene un grafo de conocimiento del código generado con Graphify en `graphify-out/`:

- `GRAPH_REPORT.md` — reporte completo: god nodes, comunidades por cohesión, conexiones inferidas, ciclos de imports, nodos aislados.
- `graph-summary.md` — resumen curado en formato Obsidian (wikilinks) de ese reporte.
- `graph.html` — visualización interactiva (abrir en navegador).
- `graph.json` / `manifest.json` — datos crudos del grafo.

**Cuándo consultarlo:** antes de una revisión de arquitectura, un refactor grande, o al evaluar si un módulo está bien encapsulado, leer `graphify-out/GRAPH_REPORT.md` (o `graph-summary.md`) en vez de solo grepear el código — el reporte ya tiene cohesión por comunidad, god nodes y relaciones cross-módulo que no son obvias archivo por archivo.

**Regenerar el grafo:** el CLI `graphify` corre en la máquina del usuario (no en el sandbox del agente), instalado vía `uv` (`graphifyy`). Si el reporte está desactualizado respecto al código, pedirle al usuario que corra `graphify` de nuevo en la raíz del proyecto y avisar cuando esté listo para releer.

---

## Archivos de configuración sensibles

- `lib/firebase_options.dart` — **SÍ está en git** (generado por `flutterfire configure`). Contiene claves cliente de Firebase (Web/Android), que no son secretas por diseño: el acceso real está protegido por Firestore Security Rules y App Check, no por ocultar este archivo. Mantenerlo trackeado es intencional para que cualquier clone/CI pueda compilar sin pasos extra.
- `android/key.properties` — firma release Android (basado en `key.properties.example`). NO en git.
- `android/local.properties` / `android/gradle.properties` — `MAPS_API_KEY`. NO en git.

---

## Convenciones de código

- Arquitectura: MVVM. View no tiene lógica de negocio.
- Estado: `ChangeNotifier` + `Provider`. No usar `setState` en pantallas complejas.
- Nomenclatura: archivos en español (legacy) y en inglés (módulos nuevos). Clases en PascalCase.
- Sin comentarios redundantes. Solo comentar el "por qué" si no es obvio.
- Screenutil: diseño base `390×844`. Usar `.w`, `.h`, `.sp` para responsividad.

---

## Riesgos técnicos activos (auditoría completa: 2026-08-06)

1. Arquitectura híbrida: flujos legacy en `screens/` conviven con `caracteristicas/` y
   `features/`. Riesgo de duplicidad.
2. Listeners de Firestore en algunas vistas (no en ViewModel). Refactorizar progresivamente.
3. Normalización de estado de solicitud en múltiples puntos. `SolicitudEstado.normalize()`
   debe ser la fuente única.
4. Claves sensibles potencialmente embebidas en código; moverlas a configuración externa.
5. **Esquema de `solicitudes` denormalizado.** El origen se escribe 3 veces en 3 tipos
   (`cliente.ubicacion`, `origen`, `ubicacion_inicial` como `GeoPoint`) y nada los
   mantiene sincronizados; `origen` y `destino` usan claves distintas para lo mismo
   (`address`/`title` vs `direccion`); el precio vive en 4 campos. Los lectores prueban
   todas las variantes, así que hoy no rompe, pero cualquier consumidor nuevo que elija
   "la clave equivocada" recibe `null`. Ver `test/esquema_solicitud_contrato_test.dart`,
   que fija el contrato actual.
6. **Sin recuperación ante pérdida de datos**: la base de producción tiene Point-in-Time
   Recovery y Delete Protection deshabilitados, y hay borrado duro de solicitudes.
7. Nombres de campo con espacios en Firestore: `'fecha de terminacion'`,
   `'fecha de aceptacion conductor'`.
8. **`usuarios/{uid}.deshabilitado` es 100% client-side** (auditoría 2026-09-02).
   `firestore.rules` solo lo usa para impedir que el propio dueño se lo quite; no es
   condición de `allow` en ninguna otra colección (`solicitudes`, `soporte_chats`, etc.).
   Un token de Firebase Auth ya emitido sigue siendo válido tras deshabilitar — nada
   llama `admin.auth().disableUser()` (requeriría una Cloud Function con Admin SDK, no
   implementada). El flag bloquea la navegación de la app (`initial_screen_resolver.dart`,
   `home_screen.dart`), no el acceso real a Firestore mientras el token no expire.

## Verificar antes de dar por hecho

Cosas que el código afirma y que resultaron falsas en la auditoría de 2026-08-06 —
comprobarlas contra el proyecto real, no contra los comentarios:

- Que una Cloud Function exista en producción. Había **3 declaradas y no desplegadas**
  (`cancelarSolicitudesBuscandoInactivas`, `expirarMembresiasVencidas`,
  `cancelarSolicitudPorCierreApp`). Comparar `grep '^exports\.' functions/index.js`
  contra `firebase functions:list`.
- Que un índice compuesto declarado en `firestore.indexes.json` esté desplegado.
  Estaban los dos declarados y **ninguno** desplegado (`firebase firestore:indexes`).
- Que un campo de Firestore lo escriba alguien. `usuarios/{uid}.ubicacion` se leía en
  dos sitios y **no lo escribe nadie**; la posición real vive en
  `conductores_conectados/{uid}`.
- Que `firebase.json` apunte a las apps correctas: apuntaba a apps fósiles
  (`com.example.taxi_app`) en ambas plataformas. La fuente de verdad es
  `firebase_options.dart` + los archivos nativos.
- Que el perfil del conductor viva en su propia colección `conductores`. Esta
  misma tabla lo decía así y era falso: cliente y conductor comparten
  `usuarios/{uid}` (campo `rol`/`tipoUsuario` los distingue); `conductores`
  es de solo lectura por reglas y casi sin uso en el código. Encontrado al
  investigar por qué el nombre del conductor que veía el cliente quedaba
  desactualizado (agosto 2026): la escritura vivía en `usuarios/{uid}`, y
  `solicitudes/{id}.conductor.nombre` es una copia congelada al aceptar —
  única razón por la que el cliente puede verlo, ya que las reglas no le
  permiten leer `usuarios/{uid}` de otro usuario.
