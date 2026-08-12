---
title: Análisis de grafo del código (Graphify)
type: analysis
created: 2026-07-20
updated: 2026-08-09
source_run: 2026-08-09
source_commit: 44fc290b
tags: [taxi-ya, arquitectura, graphify, code-graph]
---

# Análisis de grafo del código — Taxi Ya

Resumen en formato Obsidian del análisis generado por Graphify sobre el repo completo. Fuente completa: [[GRAPH_REPORT]] · Visualización interactiva: `graph.html` (abrir en el navegador).

> Grafo construido desde el commit `44fc290b`. Para verificar frescura: `git rev-parse HEAD` y comparar. Regenerar con `graphify update .` (sin costo de API).

## Alcance

- **5485 nodos** · **7380 relaciones** · **380 comunidades** (276 en el reporte, 104 "thin" omitidas)
- Extracción: 99% directa del código (EXTRACTED), 1% inferida semánticamente (37 edges, confianza promedio 0.82)
- 0% AMBIGUOUS

## Nodos más conectados (god nodes)

Los puntos donde más módulos convergen — candidatos naturales a revisar si se planea refactor:

1. `taxi_app (pubspec manifest)` — 46 conexiones
2. `CORE DIRECTIVE: PREMIUM MOBILE APP IMAGE DIRECTION` — 39 conexiones (skill, no código de la app)
3. `Win32Window` — 22 conexiones (boilerplate de Windows, esperable)
4. **`ConfirmarSolicitudViewModel` — 18 conexiones** ← el único god node de código de producción
5. `ClientAuthRepository` — 16 conexiones
6. `CLAUDE.md — Taxi Ya` — 16 conexiones
7. `MessageHandler` — 12 conexiones

`ConfirmarSolicitudViewModel` es el nodo de negocio más cargado del proyecto: concentra tarifa, ruta, método de pago, tipo de vehículo y creación de solicitud. Primer candidato si se busca dónde parte el módulo.

## Conexiones inferidas (no obvias en el código)

- `FakeClientAuthRepository` --implements--> `ClientAuthRepository` [EXTRACTED] — el contrato de auth está realmente cubierto por tests.
- Workflow de CI de Flutter ↔ `AGENTS.md` — semánticamente similares.
- `linux/**/CMakeLists.txt` ↔ `windows/**/CMakeLists.txt` — duplicación esperable de boilerplate desktop.

## Patrones detectados (hyperedges)

- **Firebase Backend Services** (Firestore, Auth, Storage, FCM, Crashlytics, Remote Config, App Check) — confirmado desde `pubspec.yaml` + `CLAUDE.md`.
- **Flujo de autenticación de cliente** (Google / Apple / Phone OTP) — `AppAuthAdapter` + `ClientAuthRepository` + los tres providers.
- **Tabla de servicios de `core/services`** — `FcmService`, `TrackingService`, `BackgroundTrackingService`, `NotificacionesServicio`, `MapServiceAdapter`, `RouteCacheService` [EXTRACTED 1.00].
- **Maps y geolocalización** — `google_maps_flutter` (+ android/platform_interface), `geolocator`, `geocoding`.
- **Trazabilidad de símbolos en release** (dSYM + mapping.txt): conecta [[PROCESO_DSYM_APP_STORE]], [[PROCESO_MAPPING_GOOGLE_PLAY]] y el README.
- ⚠️ **"Services Migration via Adapter/Shim"** sigue apareciendo citando `ChatServiceAdapter`, que **ya no existe en el código**. La hyperedge viene de [[MIGRATION]], no del AST — es el doc el que está desactualizado, no el grafo.

## Comunidades por cohesión

La cohesión mide qué tan interconectados están los nodos dentro de una comunidad — más alta = módulo más autocontenido.

**Cohesión más baja (≥25 nodos — candidatas a dividir):**

| Cohesión | Nodos | Comunidad |
|---|---|---|
| 0.02 | 83 | Driver Home ViewModel |
| 0.03 | 75 | Driver Trip ViewModel |
| 0.03 | 61 | Taxi Search Screen |
| 0.03 | 59 | Trip Status UI Widgets |
| 0.03 | 58 | Driver Home Screen |
| 0.03 | 57 | Client Trip ViewModel |

**Cohesión más alta (≥8 nodos — bien encapsuladas):**

- Init Shell Script (0.47)
- Firestore Rules Tests (0.41)
- Windows Window Message Handler (0.36)
- Suggestions Service (0.22)
- Heading-Oriented Map Tests (0.22)

## Cosas para revisar

- **`Driver Home ViewModel` (83 nodos, cohesión 0.02)** es la comunidad más grande y menos cohesionada del proyecto. `InicioConductorViewModel` mezcla despacho de solicitudes, contraofertas, tracking GPS y estado del mapa en un solo objeto.
- **`Driver Trip ViewModel` (75 nodos, 0.03)** — `ViajeConductorViewModel` cubre el ciclo completo `asignado → completado`. Grande por diseño, pero vale mirar si el sub-estado de contraoferta y la verificación de recogida pueden salir.
- **3852 nodos aislados** (≤1 conexión) — en su mayoría imports/destructuring de Firebase Functions (`{ initializeApp }`, `{ getMessaging }`, etc.). Esperable en ese tipo de código, no necesariamente un problema.
- **104 comunidades "thin" (<3 nodos)** omitidas del reporte — explorables con `graphify query`.
- **Sin ciclos de imports detectados.**

## Qué cambió respecto al run anterior (2026-07-14)

El refactor de `caracteristicas/` ya está reflejado: desaparecieron del grafo `RutaDestinoViewModel`, `RutaClienteDestinoView`, `DriverTripController`, `TripTrackingViewModel` y todo `features/phone_auth/screens`. Los reemplazan `ConfirmarSolicitudViewModel`, `ViajeConductorViewModel`, `ViajeClienteViewModel` y `SeleccionDestinoViewModel`. El grafo pasó de 4625 a 5485 nodos y de 241 a 380 comunidades.

## Preguntas que este grafo puede responder

- ¿Debería dividirse `InicioConductorViewModel`? (comunidad más grande, cohesión más baja del proyecto)
- ¿Qué depende de `ConfirmarSolicitudViewModel` antes de tocarlo? (`graphify affected "ConfirmarSolicitudViewModel"`)
- ¿Qué cubren realmente los tests de `firestore.rules`? (comunidad de cohesión 0.41, bien delimitada)

## Relacionado

[[CLAUDE]] · [[MIGRATION]] · [[README]]
