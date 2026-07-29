---
title: Análisis de grafo del código (Graphify)
type: analysis
created: 2026-07-20
source_run: 2026-07-14
tags: [taxi-ya, arquitectura, graphify, code-graph]
---

# Análisis de grafo del código — Taxi Ya

Resumen en formato Obsidian del análisis generado por Graphify sobre el repo completo. Fuente completa: [[GRAPH_REPORT]] · Visualización interactiva: `graph.html` (abrir en el navegador).

## Alcance

- 422 archivos · ~503.784 palabras analizadas
- **4625 nodos** · **6487 relaciones** · **241 comunidades**
- Extracción: 99% directa del código (EXTRACTED), 1% inferida semánticamente (42 edges, confianza promedio 0.82)

## Nodos más conectados (god nodes)

Los puntos donde más módulos convergen — candidatos naturales a revisar si se planea refactor:

1. `Win32Window` — 22 conexiones (boilerplate de Windows, esperable)
2. `ClientAuthRepository` — 19 conexiones
3. `pubspec.yaml` — 15 conexiones
4. `RutaDestinoViewModel` — 14 conexiones
5. Skill `project-brain` — 14 conexiones
6. `MessageHandler` — 12 conexiones
7. `SceneDelegate` — 11 conexiones
8. `CLAUDE.md` (guía del proyecto) — 11 conexiones

## Conexiones inferidas (no obvias en el código)

- `README.md` ↔ skill `project-brain` — semánticamente similares
- Workflow de CI de Flutter ↔ `CLAUDE.md` — semánticamente similares
- `README.md` ↔ `CLAUDE.md` — semánticamente similares

## Patrones detectados (hyperedges)

- **Migración de servicios vía adapter/shim**: `MapServiceAdapter`, `ChatServiceAdapter`, `ServicesAggregator` — confirma el patrón de migración no-destructiva descrito en [[MIGRATION]].
- **Ciclo de vida de `SolicitudEstado`** documentado de forma consistente en `lib/core/constants/solicitud_estado.dart`, el skill `project-brain` y `CLAUDE.md`.
- **Trazabilidad de símbolos en release** (dSYM + mapping.txt): conecta [[PROCESO_DSYM_APP_STORE]], [[PROCESO_MAPPING_GOOGLE_PLAY]] y el README.

## Comunidades por cohesión

La cohesión mide qué tan interconectados están los nodos dentro de una comunidad — más alta = módulo más autocontenido.

**Cohesión más baja (candidatas a dividir en módulos más chicos):**
- Features Trip Tracking Cliente Viewmodels (0.02, 108 nodos)
- Usuario Cliente Presentacion View — Buscando Taxi View (0.02, 91 nodos)
- Usuario Conductor Presentacion Viewmodels — Inicio Conductor View Mode (0.02, 90 nodos)

**Cohesión más alta (bien encapsuladas):**
- Assets Img — Nequi (1.00)
- .agents Skills Flutter Fix Layout Issues (0.67)
- Init (init.sh) (0.47)
- Macos Runner Tests / App Delegate (0.47)

## Cosas para revisar

- **Relación ambigua**: `AGENTS.md` ↔ `CLAUDE.md` (Taxi Ya) — Graphify no pudo clasificar la relación con confianza (`conceptually_related_to`, tag AMBIGUOUS). Vale aclarar si son redundantes o cada uno cubre algo distinto.
- **3329 nodos aislados** (≤1 conexión) — en su mayoría imports/destructuring de Firebase Functions (`{ initializeApp }`, `{ getMessaging }`, etc.). Esperable en ese tipo de código, no necesariamente un problema.
- **17 comunidades "thin" (<3 nodos)** omitidas del reporte — explorables con `graphify query`.
- **Sin ciclos de imports detectados.**

## Preguntas que este grafo puede responder

- ¿Cuál es la relación exacta entre `AGENTS.md` y `CLAUDE.md`?
- ¿Por qué `pubspec.yaml` conecta `Pubspec` con `Core — App Colores`? (alta betweenness centrality, 0.021 — es puente entre comunidades)
- ¿Debería dividirse `Features Trip Tracking Cliente Viewmodels` en módulos más chicos? (cohesión 0.018, la más baja del proyecto)

## Relacionado

[[CLAUDE]] · [[MIGRATION]] · [[README]]
