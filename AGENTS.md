# AGENTS.md

> Guía para Claude Code al trabajar en este repositorio.
> Léelo completo antes de hacer cualquier cambio. Estas reglas tienen prioridad
> sobre suposiciones por defecto.

---

## 1. Qué es este proyecto

Aplicación móvil de transporte (tipo ride-hailing) con dos roles:

- **Cliente:** crea una solicitud de viaje, ve al conductor que la acepta acercándose
  en el mapa en tiempo real, sigue el trayecto hacia su destino, chatea con el
  conductor y consulta su información.
- **Conductor:** encuentra solicitudes disponibles, ve la ubicación del cliente,
  navega hasta el punto de recogida con Google Maps, lo recoge y lo lleva al destino
  marcado de la forma más rápida. También chatea con el cliente y ve su información.

El núcleo del producto es: **matching cliente–conductor, tracking de ubicación en
tiempo real sobre el mapa, navegación, y chat entre ambas partes.**

**Estado actual:** MVP a medias, sin usuarios reales todavía. El objetivo es pulirlo,
endurecer la seguridad y **llevarlo a producción**. Trabajas sobre código que YA
existe: respétalo y mejóralo, no lo reinventes sin necesidad.

---

## 2. Stack tecnológico

- **Móvil:** Flutter + Dart (iOS y Android).
- **Backend / base de datos:** Firebase (Firestore/Realtime Database, Auth,
  Cloud Messaging para notificaciones).
- **Mapas y ubicación:** Google Maps SDK, GPS del dispositivo, y APIs de Google
  (Directions, Distance Matrix, Geocoding) para la trazabilidad de rutas en el mapa.

**No cambies** la versión de Flutter ni las dependencias core (Firebase, Google Maps,
Provider) sin avisar y justificarlo primero.

---

## 3. Arquitectura y estructura de carpetas

El proyecto usa **Clean Architecture + MVVM con Provider** como gestor de estado.

> ⚠️ Hoy hay carpetas en `lib/` que NO están bien ordenadas. Tienes permiso para
> mover y reorganizar archivos hacia la estructura objetivo de abajo cuando toques
> un área. Hazlo **por áreas/features, no todo de golpe**, y después de cada
> reorganización corre `flutter analyze` y verifica que siga limpio (no rompas
> imports).

### Estructura objetivo (feature-first + capas)

```
lib/
├── core/                  # Código transversal compartido
│   ├── constantes/        # Constantes, claves de rutas, enums globales
│   ├── errores/           # Manejo de errores y excepciones
│   ├── servicios/         # Servicios base (Firebase, ubicación, mapas, notificaciones)
│   ├── utilidades/        # Helpers, extensiones, formateadores
│   └── tema/              # Colores, tipografía, tema de la app
│
├── caracteristicas/       # Una carpeta por feature
│   ├── autenticacion/
│   │   ├── datos/          # Capa de datos: modelos, fuentes (Firebase), repos impl.
│   │   ├── dominio/        # Entidades, contratos de repositorio, casos de uso
│   │   └── presentacion/   # Vistas (UI) + ViewModels (Provider/ChangeNotifier)
│   ├── solicitud_viaje/
│   ├── mapa_seguimiento/
│   ├── chat/
│   └── perfil/
│
└── main.dart
```

### Reglas de las capas (Clean Architecture)

- **`dominio`** no depende de nada externo (ni Flutter, ni Firebase). Solo lógica de
  negocio pura: entidades, casos de uso y contratos (interfaces) de repositorio.
- **`datos`** implementa los contratos de `dominio` y habla con Firebase / Google APIs.
- **`presentacion`** contiene la UI y los **ViewModels** (`ChangeNotifier` expuestos
  con Provider). La UI no llama a Firebase directamente: pasa por el ViewModel → caso
  de uso → repositorio.
- La dependencia siempre apunta hacia adentro: `presentacion → dominio ← datos`.

---

## 4. Comandos

```bash
flutter pub get        # Instalar dependencias
flutter run            # Correr la app
flutter analyze        # Análisis estático — DEBE quedar limpio antes de terminar
dart format .          # Formatear el código
flutter test           # Correr tests
```

**Antes de dar por terminado cualquier cambio**, corre como mínimo:
`dart format .` → `flutter analyze` → `flutter test`. Los tres deben pasar sin errores.

---

## 5. Convenciones de código

- **Idioma: ESPAÑOL.** Nombres de variables, clases, métodos, archivos, carpetas,
  campos de Firestore y comentarios van en español.
  - Clases en `PascalCase`: `SolicitudViaje`, `RepositorioConductor`.
  - Variables y métodos en `camelCase`: `crearSolicitud()`, `ubicacionActual`.
  - Archivos en `snake_case`: `solicitud_viaje.dart`, `repositorio_conductor.dart`.
  - Estados y valores del dominio en español: `buscando`, `asignado`, `en_ruta`.
- Sigue el linter del proyecto (`analysis_options.yaml`). Si no existe uno con reglas
  estrictas, créalo basándote en `flutter_lints` y avísame.
- Evita la lógica de negocio dentro de los widgets: vive en casos de uso / ViewModels.
- Comentarios solo donde aporten; el código en español ya debe leerse claro.

---

## 6. Tests — OBLIGATORIOS

**Todo cambio nuevo (feature o fix) DEBE venir acompañado de sus tests.** No se
considera terminado un cambio sin tests que pasen.

- **Unitarios:** para casos de uso y lógica de negocio (cancelaciones, transiciones de
  estado, cálculos de ruta/tarifa).
- **De widget:** para la UI relevante del cambio.
- **De integración:** para los flujos críticos — crear solicitud, matching, tracking
  en el mapa, y chat.

Como hoy NO hay tests, ve creando la base de testing a medida que tocas cada área.

---

## 7. Firebase, seguridad y secretos

### 🔴 TAREA CRÍTICA PENDIENTE: no existen `firestore.rules`

El proyecto **no tiene reglas de seguridad de Firestore escritas todavía**. Esto es
**bloqueante para producción**: sin reglas, cualquiera podría leer ubicaciones en
tiempo real, chats y datos personales de otros usuarios.

- Antes de producción hay que escribir `firestore.rules` que garanticen, como mínimo:
  - Un usuario solo lee/escribe sus propios datos.
  - La ubicación de un viaje solo es legible por el cliente y el conductor de ESE viaje.
  - Los mensajes de chat solo son accesibles para los dos participantes del viaje.
- **NUNCA toques ni relajes las reglas de Firestore sin avisarme primero.**

### Secretos y claves

- **NUNCA** hagas commit de claves, secretos ni credenciales (API keys de Google Maps,
  config de Firebase con datos sensibles, archivos de servicio).
- Las API keys y configuración sensible deben ir por `--dart-define` / variables de
  entorno y/o archivos ignorados en `.gitignore`, nunca hardcodeadas en el código.
- Si encuentras un secreto commiteado, avísame de inmediato; no lo dejes pasar.

---

## 8. Reglas de negocio

### Estados de la solicitud / viaje

Flujo propuesto (CONFIRMAR — ver nota abajo):

```
buscando → asignado → en_camino → en_espera → en_ruta → completado
                                                      ↘ cancelado
```

- `buscando` — solicitud creada, esperando que un conductor la acepte.
- `asignado` — un conductor aceptó la solicitud.
- `en_camino` — el conductor va en camino al punto de recogida.
- `en_espera` — el conductor llegó y espera al cliente.
- `en_ruta` — viaje en curso hacia el destino.
- `completado` — viaje finalizado.
- `cancelado` — solicitud cancelada.

> ⚠️ **CONFIRMAR:** en la lista original que diste apareció **"en ruta" dos veces**.
> Arriba propuse un orden lógico. Antes de codificar las transiciones de estado,
> confirma la lista y el orden definitivos. No inventes transiciones sin confirmación.

Una vez confirmados, las transiciones deben respetarse estrictamente: un estado no
puede saltarse pasos (p. ej. no se pasa a `completado` sin haber estado `en_ruta`).

### Compartir ubicación

- La ubicación **solo se comparte cuando el estado de la solicitud es `asignado` o
  `en_ruta`** (y los estados intermedios del viaje activo que se confirmen).
- En cualquier otro estado, **NO se comparte ubicación**. Esto es una regla de
  privacidad: no rastrees ni expongas la ubicación de un usuario fuera de un viaje activo.

### Cancelaciones del cliente

- El cliente puede cancelar hasta **5 solicitudes** creadas.
- A la **6ª** se activa un **cooldown (timeout) de 5 minutos** durante el cual NO
  puede crear nuevas solicitudes.
- Implementa esto de forma robusta (el contador y el cooldown deben sobrevivir a
  reinicios de la app; valídalo también del lado de Firestore, no solo en el cliente).

---

## 9. Reglas duras — NUNCA hagas esto

- ❌ **Nunca** hagas commit de claves, secretos ni credenciales.
- ❌ **Nunca** toques ni relajes las reglas de Firestore sin avisar primero.
- ❌ **Nunca** borres datos de producción.
- ❌ **Nunca** hagas push directo a `main`.
- ❌ **No** añadas paquetes/dependencias pesadas sin justificarlo y consultarlo.
- ❌ **No** cambies la versión de Flutter ni las dependencias core (Firebase, Google
  Maps, Provider) sin avisar.
- ❌ **No** des por terminado un cambio si `flutter analyze` o `flutter test` fallan.
- ❌ **No** muevas archivos masivamente sin verificar después que `flutter analyze`
  queda limpio.
- ❌ **No** metas lógica de negocio dentro de los widgets.
- ❌ **No** llames a Firebase/Google APIs directamente desde la capa de presentación.

---

## 10. Commits y ramas

Aún no hay convención definida. Usa esta (todo en **español**):

### Commits — Conventional Commits

```
feat: agregar cancelacion con cooldown de 5 minutos
fix: corregir ubicacion que no se ocultaba al completar viaje
refactor: reorganizar carpeta de chat segun clean architecture
test: agregar tests del caso de uso crear solicitud
docs: actualizar AGENTS.md
```

Tipos: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`.

### Ramas

```
feature/descripcion-corta
fix/descripcion-corta
refactor/descripcion-corta
```

Nunca trabajes ni hagas push directo sobre `main`.

---

## 11. Checklist antes de producción (pendientes detectados)

- [ ] Escribir `firestore.rules` (🔴 crítico — seguridad de datos y ubicación).
- [ ] Confirmar y codificar la lista/orden definitivos de estados del viaje.
- [ ] Reorganizar `lib/` a la estructura objetivo de la sección 3.
- [ ] Crear la base de tests (unitarios, widget, integración) e ir cubriendo lo crítico.
- [ ] Asegurar que ninguna clave/secreto esté en el repo; mover a `--dart-define`/env.
- [ ] Validar la regla de cancelaciones (5 + cooldown) del lado servidor.
- [ ] Definir `analysis_options.yaml` con reglas de lint estrictas.

---

_Si algo no está cubierto en este documento, pregunta antes de asumir._
