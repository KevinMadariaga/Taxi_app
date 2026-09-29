# Revisión de actualización Flutter — Taxi Ya (`taxi_app`)

**Fecha:** 29/09/2026 · **Versión revisada:** `1.0.9+69` (commit `f5d11cc1`)
**Alcance:** contrastar el código actual contra lo más reciente y estable del ecosistema Flutter (SDK, clases/arquitectura, GPS/ubicación/movimiento, rendimiento, seguridad y testing).

---

## Instrucciones para el agente

1. Lee primero `CLAUDE.md` y `AGENTS.md`: sus convenciones mandan sobre este documento (nombres en español, Conventional Commits en español, tests obligatorios en cada cambio).
2. Trabaja **un hallazgo a la vez**, en el orden de la sección "Plan de ejecución". Cada hallazgo es un commit (o PR) independiente.
3. Tras cada cambio, `flutter analyze` y `flutter test` deben quedar en verde. Si tocas reglas, también `rules-tests/`.
4. **Antes de cambiar código, verifica el hallazgo.** Las líneas citadas son de la revisión del 29/09/2026 y pueden haberse movido. Si un hallazgo ya no aplica, márcalo ✅ con una nota y sigue.
5. No hagas migraciones grandes (Provider → Riverpod, Material → `material_ui`) salvo que el hallazgo lo pida explícitamente. Están marcadas como post-lanzamiento.
6. Actualiza la columna **Estado** de este archivo al terminar cada punto: ⬜ pendiente · 🔄 en curso · ✅ hecho · ⏭️ descartado (con motivo).

**Madurez de lo recomendado:** 🟢 estable, adoptar · 🟡 depende del caso · 🟠 vigilar · 🔴 evitar.
**Prioridad:** P0 bloquea el lanzamiento · P1 antes del lanzamiento · P2 post-lanzamiento.

---

## 0. Contexto: qué hay de nuevo en Flutter (sept 2026)

- **Flutter 3.47** es la versión estable desde el 12/08/2026.
  - Material y Cupertino pasan a paquetes independientes (`material_ui` / `cupertino_ui` 1.0). Los del núcleo se marcan obsoletos en **noviembre de 2026**. La migración se hace con `dart fix --apply --code=migrate_design_widgets`.
  - Mínimo iOS 15.
  - Swift Package Manager ya cubre 92 de los 100 plugins principales, y CocoaPods queda en mantenimiento.
  - iOS 27 exige UIScene.
  - Valores por defecto de Android: compile/target SDK 36, minSdk 24, AGP 9.1, Kotlin 2.4, Gradle 9.3, Java 17.
  - Widget Previews pasa a estable.
- 🟢 Impeller es el motor por defecto en iOS y en Android API 29+.
- 🟢 Dart: dot shorthands (3.10) y parámetros nombrados privados (3.12).
- 🔴 Los macros de Dart fueron cancelados oficialmente: seguir con `freezed` / `json_serializable`.
- **Gestión de estado:**
  - 🟢 Riverpod 3 es el estándar de facto para código nuevo.
  - 🟡 Provider está vigente pero ya se considera legado.
  - 🔴 GetX no se recomienda.
- **Paquetes clave hoy:** `geolocator` 14.1.1 (publicado el 28/09/2026) y `google_maps_flutter` 2.18.2 con Advanced Markers.
- **iOS Maps SDK:** la versión 10.x exige iOS 16 y la 9.x soporta iOS 15.

---

## 1. Lo que ya está bien (no tocar)

- `firestore.rules` existe, con deny por defecto (`allow read, write: if false`) y suite de pruebas en `rules-tests/`. `storage.rules` también.
- Los secretos no están en git:
  - `env.json`, `key.properties`, `*.jks` y `ios/Flutter/Secrets.xcconfig` están ignorados.
  - La key de Maps de iOS se lee de `Info.plist` y ya no está hardcodeada.
- `tracking_service.dart` implementa bien el tracking del conductor:
  - `AndroidSettings` con `foregroundNotificationConfig`, `distanceFilter` de 15 m y `intervalDuration`.
  - `AppleSettings` con background.
  - Throttle de escritura (mínimo 5 s + distancia) y keep-alive.
- Permisos de ubicación completos: Android (`ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`, servicio con `foregroundServiceType="location"`) e iOS (`UIBackgroundModes: location` y los tres textos `NSLocation*`).
- UIScene ya adoptado (`UIApplicationSceneManifest` en `Info.plist`).
- Target iOS en 15.5, compatible con el mínimo de Flutter 3.47.
- El marcador del conductor rota según el rumbo (`viaje_cliente_screen.dart:770`, test `mapa_orientado_al_rumbo_test.dart`).
- Crashlytics activo, R8/minify en release, persistencia offline de Firestore, 57 archivos de test y CI con analyze + test.
- No hay `print(` sueltos en `lib/`. Se usan `CachedNetworkImage` y `cacheWidth` en la mayoría de imágenes.

---

## 2. Hallazgos

### A. SDK, plataforma y dependencias

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| A1 | P1 | El proyecto está en **Flutter 3.44.3 / Dart 3.12.2** y la estable actual es **3.47** | `.dart_tool/version`; `pubspec.lock` → `flutter: ">=3.44.0"` | Actualizar a 3.47.x en una rama propia. Revisar breaking changes en docs.flutter.dev/release/breaking-changes | `flutter --version` = 3.47.x; analyze y test en verde; build Android e iOS OK | ⬜ |
| A2 | P1 | El CI usa `channel: stable` **sin fijar versión**: ya compila con 3.47 mientras el equipo local usa 3.44 | `.github/workflows/flutter-ci.yml` (`subosito/flutter-action`) | Fijar `flutter-version: 3.47.x` (o la que se adopte en A1) y mantenerla igual a la local. Opcional: FVM (`.fvmrc`) | CI y local usan la misma versión | ⬜ |
| A3 | P1 | `environment: sdk: ^3.10.7` está desfasado frente al lock (Dart ≥ 3.12) | `pubspec.yaml` | Subir a `sdk: ^3.12.0` (o el Dart que traiga 3.47) | `flutter pub get` sin avisos | ⬜ |
| A4 | P1 | Dependencias atrasadas: `geolocator` 14.0.2 (hay 14.1.1), `google_maps_flutter` 2.18.0 (hay 2.18.2), `google_sign_in` 6.3.0 (existe una línea 7.x con API nueva), entre otras | `pubspec.lock` | `flutter pub outdated`; subir parches/menores. `google_sign_in` 7.x cambia la API: hacerlo en un commit aparte y con tests | Sin dependencias con parches pendientes; login con Google probado en ambos SO | ⬜ |
| A5 | P1 | Override fijo `path_provider_foundation: 2.4.1` (el propio comentario pide revisarlo) | `pubspec.yaml`, `dependency_overrides` | Quitar el override, `pod install` / build iOS y, si el conflicto ya no existe, dejarlo fuera | Sin `dependency_overrides`, o justificación actualizada | ⬜ |
| A6 | P1 | Toolchain Android por debajo de lo verificado con 3.47: AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14, plugin google-services 4.3.15 | `android/settings.gradle.kts`, `gradle-wrapper.properties` | Tras A1, subir AGP (hacia 9.1), Kotlin (2.4), Gradle (9.3) y google-services (4.4.x) según lo que pida `flutter build` | `flutter build appbundle --release` sin warnings de toolchain | ⬜ |
| A7 | P2 | iOS: CocoaPods está en modo mantenimiento | `ios/Podfile` | Habilitar Swift Package Manager (`flutter config --enable-swift-package-manager`), compilar y validar que Maps, Firebase y ML Kit resuelvan | Build iOS OK con SPM | ⬜ |
| A8 | P2 | Inconsistencia de target en el Podfile: `platform :ios, '15.5'`, pero `post_install` fuerza los pods a `15.0` | `ios/Podfile:2` y `:53` | Unificar en 15.5 | Un único valor de target | ⬜ |
| A9 | P2 | Material y Cupertino del núcleo se marcan obsoletos en nov 2026 | `pubspec.yaml` (`uses-material-design`) | Tras A1, migrar con `dart fix --apply --code=migrate_design_widgets` en una rama aparte | Sin avisos de deprecación de Material | ⬜ |
| A10 | P2 | `CLAUDE.md` está desactualizado (dice versión `1.0.1+24`) | `CLAUDE.md`, sección "Descripción" | Actualizar versión, SDK de Flutter y lo que cambie en A1–A9 | Coincide con `pubspec.yaml` | ⬜ |

### B. Clases y arquitectura

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| B1 | P2 | Estructura mixta: conviven `caracteristicas/` (patrón oficial) con `features/`, `screens/`, `widgets/`, `presentation/` y `data/` (legado) | Árbol de `lib/` | Seguir migrando **área por área** a `caracteristicas/<feature>/{datos,dominio,presentacion}` según `CLAUDE.md`. Empezar por `features/trip_tracking_cliente` y `features/resumen_viaje` | Cada área migrada con analyze/test en verde y `arquitectura_capas_test.dart` pasando | ⬜ |
| B2 | P2 | Hay 53 llamadas a `Navigator.push` dispersas y no se usa router declarativo | `grep Navigator.push lib` | Evaluar `go_router` (🟢) con rutas tipadas; no migrar antes del lanzamiento | Decisión documentada en `CLAUDE.md` | ⬜ |
| B3 | P2 | Modelos mutables sin codegen | `lib/core/modelos`, `lib/data/models` | Para modelos nuevos: `freezed` + `json_serializable`; estados del viaje como `sealed class` con `switch` exhaustivo | Aplicado en código nuevo | ⬜ |
| B4 | P2 | Provider (🟡). Riverpod 3 es el estándar para código nuevo | `pubspec.yaml` | **No migrar antes del lanzamiento.** Después, evaluar Riverpod por feature nueva | Decisión documentada | ⬜ |
| B5 | P2 | Lints básicos (`flutter_lints`) y CI con `--no-fatal-infos` | `analysis_options.yaml`, `flutter-ci.yml` | Añadir reglas extra (p. ej. `prefer_const_constructors`, `avoid_print`, `cancel_subscriptions`, `close_sinks`, `unawaited_futures`) o `very_good_analysis` de forma gradual | Analyze en verde con las nuevas reglas | ⬜ |

### C. GPS, ubicación y movimiento

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| C1 | P1 | **Sin detección de ubicación falsa (mock/GPS spoofing)** para el conductor | `grep isMocked lib` → 0 resultados | En `tracking_service.dart`, revisar `position.isMocked` (Android) y reportar o bloquear según la regla de producto. Complementar con D2 (`freerasp`) | Test unitario: una posición con `isMocked=true` no se publica o queda marcada | ⬜ |
| C2 | P1 | `UbicacionServicio` usa `distanceFilter: 1` y `LocationAccuracy.high` por defecto: emite casi en cada metro y dispara rebuilds y consumo de batería | `lib/core/services/ubicacion_servicio.dart:47`, `:70` | Subir el default (5–10 m en UI del cliente). Separar la precisión según el caso (UI vs. tracking del conductor, que ya usa 15 m) | Menos eventos por minuto con la app quieta; tests actualizados | ⬜ |
| C3 | P1 | Suscripciones `.listen` sin `cancel()` explícito | `background_tracking_service.dart:106,144`; `fcm_service.dart:248,251,254` | Guardar las `StreamSubscription` y cancelarlas en `stop()`/`dispose()`. Evitar suscripciones duplicadas si `init()` se llama más de una vez | Test: llamar `init()` dos veces no duplica handlers | ⬜ |
| C4 | P1 | El marcador del conductor rota, pero hay que confirmar que el **desplazamiento se interpola** en producción. `conductor_movement_simulator.dart` existe, pero hay que verificar que se use con datos reales y no solo en QA | `features/trip_tracking_cliente/controllers/conductor_movement_simulator.dart` | Verificar. Si el marcador "salta" entre updates de 5 s, animar la posición (Tween de lat/lng a unos 60 fps durante el intervalo) | En dispositivo real el marcador se desliza sin saltos | ⬜ |
| C5 | P2 | No se usan Advanced Markers | `grep mapId lib` → 0 | Opcional: crear un Map ID en Google Cloud y migrar el marcador del carro a `GoogleMapMarkerType.advancedMarker` | Marcador renderizado con Advanced Markers en ambos SO | ⬜ |
| C6 | P1 | Validación en campo del tracking en segundo plano con las versiones nuevas del SO | — | Probar el turno del conductor con pantalla apagada 15 min en Android 14+ (fabricantes agresivos: Xiaomi, Samsung) e iOS 17+. Si falla o consume mucha batería, evaluar `flutter_background_geolocation` (🟡, de pago) | Sin huecos de más de 30 s en la ubicación publicada | ⬜ |

### D. Seguridad (OWASP MASVS)

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| D1 | **P0** | **App Check solo está activo en iOS**: en Android no se activa porque Play Integrity no está configurado. Cualquier cliente Android modificado o script puede llamar a Firestore y Functions | `lib/core/helpers/firebase_helper.dart:27-41` | Registrar la huella SHA-256 de release (Play App Signing) en Firebase, habilitar Play Integrity y activar `AndroidProvider.playIntegrity` en release. Probar primero en modo monitor antes de hacer enforcement | Métricas de App Check con más del 95 % de solicitudes verificadas en Android y FCM funcionando | 🔄 Código hecho (29/09): `AndroidPlayIntegrityProvider` + App Attest en release (`firebase_helper.dart`, test `firebase_helper_app_check_test.dart`). Verificado: proveedor Play Integrity ya registrado en Firebase y todos los servicios en `UNENFORCED` (modo monitor). **Falta en consola:** registrar la SHA-256 de la llave de firma de Play (la de subida `95:F3:15:BD…` no está registrada), confirmar la API Play Integrity vinculada en Play Console, publicar y medir métricas antes de enforcement |
| D2 | P1 | Sin protección RASP (root, jailbreak, Frida, emulador, tampering) | `pubspec.yaml` (no hay `freerasp`) | Integrar `freerasp` (Talsec) y definir la reacción ante cada amenaza (registrar en Crashlytics o bloquear el modo conductor) | Detecta emulador/root en pruebas; tests del handler | ⬜ |
| D3 | P1 | Builds de release sin ofuscación de Dart | `Makefile` (`build-android`, `build-ios`) | Añadir `--obfuscate --split-debug-info=build/symbols` y subir los símbolos a Crashlytics (`firebase crashlytics:symbols:upload`); actualizar `PROCESO_*.md` | Los stack traces de Crashlytics siguen legibles | ⬜ |
| D4 | P1 | Las reglas documentan limitaciones abiertas: un conductor puede escribir la solicitud completa en estado `buscando`; el aislamiento por gremio de admin es solo del lado del cliente | `firestore.rules:8-27` | Restringir campos con `request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])` para la aceptación/contraoferta; filtrar por `adminId` en la regla | Nuevos casos en `rules-tests/solicitudes.test.js` pasan | 🔄 Parte conductores ✅ (29/09): `escrituraDeConductorAjeno()` limita a un conductor no asignado a aceptar para sí mismo o escribir su propia contraoferta; 8 tests nuevos, 147/147 en verde. **Falta desplegar** las reglas. Parte gremio ⏭️ no aplica: ya no existen gremios; el admin es un único nivel (rol `admin` puesto a mano en la base) y debe ver a todos los conductores |
| D5 | P1 | Los tests de reglas (`rules-tests/`) y los de Functions **no corren en CI** | `.github/workflows/flutter-ci.yml` | Añadir un job con el Emulator Suite: `firebase emulators:exec "npm test"` en `rules-tests/` y en `functions/` | CI falla si una regla se rompe | ⬜ |
| D6 | P1 | Cloud Functions sin `enforceAppCheck` | `grep enforceAppCheck functions` → 0 | Tras D1, añadir `enforceAppCheck: true` a las callables | Llamadas sin token rechazadas | ⬜ |
| D7 | P1 | Permiso `AD_ID` declarado sin SDK de anuncios en el proyecto | `AndroidManifest.xml:22` | Quitarlo (con `tools:node="remove"` si viene de una dependencia) y actualizar la declaración de Advertising ID en Play Console | Merged manifest sin `AD_ID` | ⬜ |
| D8 | P2 | `user_role`, `user_uid` e `is_logged_in` guardados en `SharedPreferences` | `session_helper.dart:21-34`, `auth_service.dart:94` | No es un secreto, pero confirmar que el rol **solo decide UI** y que toda autorización real vive en las reglas. Si llega a haber tokens, usar `flutter_secure_storage` | Revisión documentada | ⬜ |
| D9 | P2 | La key de Static Maps va en el binario (`--dart-define`), algo inevitable en el cliente | `app_constants.dart:24` | Verificar en Google Cloud que esté **restringida por app** (package + SHA-1 / bundle ID) y **por API** | Key restringida | ⬜ |
| D10 | P2 | Sin auditoría de vulnerabilidades de dependencias | — | Añadir `osv-scanner --lockfile=pubspec.lock` y `npm audit` en `functions/` al CI | Reporte en CI | ⬜ |

### E. Rendimiento

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| E1 | P1 | 162 `setState` y 75 `notifyListeners`, con pocos `Selector` (9): riesgo de rebuilds de pantalla completa con cada update de ubicación | `grep` en `lib/` | Perfilar `viaje_cliente_screen` y `viaje_conductor_screen` con DevTools → *Track widget rebuilds*. Aislar el `GoogleMap` y las tarjetas con `Selector` / `ValueListenableBuilder` y `const` | El mapa no se reconstruye cuando solo cambia el texto de la tarjeta | ⬜ |
| E2 | P1 | Sin medición en gama baja | — | `flutter run --profile` en un Android de gama baja: los frames deben estar por debajo de 16 ms en el viaje activo | Captura de DevTools adjunta al PR | ⬜ |
| E3 | P2 | 16 `ListView(` con `children` fijos | `grep "ListView(" lib` | Revisar cuáles pueden crecer (historial, chat, listas de admin) y pasarlos a `.builder` | Listas largas con `.builder` | ⬜ |
| E4 | P2 | 2 `Image.network` sin caché | `grep Image.network lib` | Cambiar a `CachedNetworkImage` con `memCacheWidth` | 0 `Image.network` | ⬜ |
| E5 | P2 | Tamaño de la app sin medir | — | `flutter build apk --analyze-size` y registrar la línea base | Línea base documentada | ⬜ |
| E6 | P2 | Sin Firebase Performance Monitoring | `pubspec.yaml` | Opcional: `firebase_performance` con trazas en solicitar viaje y aceptar viaje | Trazas visibles en la consola | ⬜ |

### F. Testing y herramientas

| ID | Prioridad | Hallazgo | Evidencia | Acción | Criterio de aceptación | Estado |
|---|---|---|---|---|---|---|
| F1 | P2 | No hay tests E2E con permisos nativos (ubicación, notificaciones) | `integration_test/` no existe | Adoptar `patrol` (🟢) para el flujo completo: solicitar → aceptar → finalizar | 1 flujo E2E corriendo en local | ⬜ |
| F2 | P2 | Mocks manuales / `fake_*` | `dev_dependencies` | Para tests nuevos: `mocktail` (🟢, sin codegen) | — | ⬜ |
| F3 | P2 | Golden tests | — | Si se agregan, usar `alchemist` (`golden_toolkit` está descontinuado) y solo para componentes | — | ⬜ |
| F4 | P2 | Tooling de IA | — | Instalar el MCP oficial: `claude mcp add --transport stdio dart -- dart mcp-server` (analyze, tests y hot reload desde el agente) | Configurado | ⬜ |

---

## 3. Plan de ejecución (orden sugerido)

**Antes del lanzamiento**

1. **D1** App Check en Android → **D6** `enforceAppCheck` en Functions.
2. **D4** endurecer reglas + **D5** reglas en CI.
3. **C1** mock location + **D2** `freerasp`.
4. **D3** ofuscación + **D7** quitar `AD_ID`.
5. **C2**, **C3**, **C4** ubicación y suscripciones → **C6** prueba de campo.
6. **E1**, **E2** perfilado del mapa en gama baja.
7. **A2** fijar versión en CI → **A1**, **A3**, **A4**, **A5**, **A6** actualizar a Flutter 3.47 y dependencias (rama propia, con prueba completa en dispositivos).

**Después del lanzamiento**

8. **A7** SPM, **A8**, **A9** migración a `material_ui` (antes de nov 2026), **A10**.
9. **B1** migración de carpetas por área, **B5** lints.
10. **B2**, **B3**, **B4** decisiones de router, modelos y estado.
11. **E3–E6**, **D8–D10**, **F1–F4**.

---

## Fuentes

- [What's new in Flutter 3.47](https://flutter.dev/blog/whats-new-in-flutter-3-47)
- [Flutter release notes](https://docs.flutter.dev/release/release-notes)
- [Flutter 3.47.0 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0)
- [Breaking changes](https://docs.flutter.dev/release/breaking-changes)
- [geolocator — pub.dev](https://pub.dev/packages/geolocator)
- [google_maps_flutter — pub.dev](https://pub.dev/packages/google_maps_flutter)
- [flutter_background_geolocation — pub.dev](https://pub.dev/packages/flutter_background_geolocation)
- [LeanCode — Geolocation in Flutter](https://leancode.co/glossary/geolocation-in-flutter)
- [Talsec — OWASP Top 10 for Flutter](https://docs.talsec.app/appsec-articles/articles/owasp-top-10-for-flutter-m1-mastering-credential-security-in-flutter)
- [Talsec — OWASP MAS y RASP en Flutter](https://docs.talsec.app/appsec-articles/articles/how-to-hack-and-protect-flutter-apps-owasp-mas-and-rasp.-pt.-2-3)
- [Dart & Flutter MCP server](https://docs.flutter.dev/ai/mcp-server)
