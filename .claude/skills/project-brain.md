---
name: project-brain
description: >
  Inject full architectural context for the Taxi Ya (taxi_app) Flutter project.
  Invoke at the start of any new task so Claude has a complete mental map —
  folder structure, state machine, critical files, Firestore schema, services,
  and active risks — without exploring the codebase from scratch.
---

# Project Brain — Taxi Ya (taxi_app)

Flutter app · MVVM + Provider · Firebase backend
Roles: **cliente** · **conductor** · **administrador**

---

## Estructura `lib/`

```
core/          → Infraestructura transversal: constantes, tema, auth, servicios
  auth/        → AppAuthAdapter (ClientAuthRepository)
  constants/   → solicitud_estado.dart  ← FUENTE ÚNICA DE VERDAD para estados
  services/    → Servicios singleton (ver tabla abajo)
domain/        → Entidades, contratos de repositorio, usecases
data/          → Implementaciones Firebase, datasources, models
presentation/  → Pantallas modernas: splash, login, complete_profile + ViewModels
features/      → Módulos por feature (inglés, arquitectura limpia progresiva):
  phone_auth/            → OTP, registro cliente/conductor, admin panel
  trip_tracking_cliente/ → Tracking activo del cliente
  driver_trip/           → Vista y lógica del conductor durante viaje
  resumen_viaje/         → Resumen post-viaje y calificación
screens/       → Flujos legacy productivos (español):
  usuario_cliente/presentacion/   → home, mapa, buscando, ruta, resumen
  usuario_conductor/presentacion/ → inicio, ruta, historial
widgets/       → Componentes UI reutilizables globales
routes/        → AppRoutes (solo '/' y '/login'; el resto es imperativo)
helper/        → firebase_helper, permisos_helper, session_helper, map_helper
```

---

## Máquina de estados — `SolicitudEstado`

`lib/core/constants/solicitud_estado.dart`

```
buscando      → cliente espera conductor
asignado      → conductor asignado           (isSesionActiva)
en espera     → conductor confirmó; 180 s para que cliente confirme
en camino     → conductor en ruta al cliente (isSesionActiva)
en ruta       → viaje iniciado               (isSesionActiva)
completado    → TERMINAL
cancelado     → TERMINAL
sin respuesta → TERMINAL — timeout 180 s
```

**Regla crítica:** Usar siempre `SolicitudEstado.normalize(raw)`.
Nunca comparar strings crudos de Firestore.

Métodos: `normalize(raw)` · `isTerminal(normalized)` · `isSesionActiva(normalized)`

---

## Flujo de solicitud — archivos clave

| Paso | Archivo | Método |
|------|---------|--------|
| 1. Crear solicitud | `screens/usuario_cliente/presentacion/viewmodels/mapapreview_viewmodel.dart` | `crearSolicitud()` |
| 2. Escuchar estado (buscando) | `screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart` | `iniciarEscucha()` |
| 3. Reaccionar a cambio | `features/trip_tracking_cliente/controllers/solicitud_estado_controller.dart` | `handleEstadoCambio()` |
| 4. Tracking cliente | `features/trip_tracking_cliente/views/trip_tracking_screen.dart` | — |
| 5. Recepción conductor | `screens/usuario_conductor/presentacion/viewmodel/InicioConductorViewModel.dart` | listener `_subscribeSolicitudes()` |
| 6. Vista viaje conductor | `features/driver_trip/screens/driver_trip_screen.dart` | — |

Campos escritos en `crearSolicitud()`: `tipoVehiculo` ('carro'|'moto'), `tarifa{}`,
`origen{}`, `destino{}`, `cliente{}`, `contraofertas{}`, `estado: 'buscando'`

### Contra-ofertas (multi-conductor)

- Conductor escribe en `contraofertas.{conductorId}` (map en el doc de solicitud).
- También escribe campo legacy `contraoferta` para compatibilidad.
- Cliente ve todas las ofertas como tarjetas superpuestas sobre el mapa (`buscando_taxi_view.dart`).
- `aceptarContraofertaDeConductor(conductorId)` → transacción Firestore: estado='asignado', limpia mapa.
- `rechazarContraofertaDeConductor(conductorId)` → `FieldValue.delete()` de la entrada específica.

---

## Flujo de autenticación

| Componente | Archivo |
|-----------|---------|
| Auth adapter | `lib/core/auth/app_auth_adapter.dart` |
| Decisión pantalla inicial | `lib/core/services/auth_service.dart` → `determineInitialScreen()` |
| Persistencia de sesión | `SessionHelper` + SharedPreferences |

- **Clientes**: Google / Apple / OTP telefónico
- **Conductores**: email+password (admin los crea); `tipoVehiculo` guardado en perfil
- **Admins**: flujo propio → colección `administradores/{uid}`

Colecciones por rol: `administradores/{uid}` · `usuarios/{uid}` (clientes) · `conductor/{uid}`

---

## Colecciones Firestore

| Colección | Campos clave |
|-----------|-------------|
| `solicitudes` | `estado`, `cliente{}`, `conductor{}`, `tarifa{}`, `origen{}`, `destino{}`, `tipoVehiculo`, `contraofertas{}` (map por conductorId), `updatedAt` |
| `usuarios` | `nombre`, `apellido`, `telefono`, `fotoUrl`, `rol`, `isProfileComplete`, `tipoUsuario`, `disponible`, `ubicacion{}` |
| `conductor` | Perfil conductor (colección separada de `usuarios`); incluye `tipoVehiculo` |
| `cliente` | Perfil cliente legacy (colección separada de `usuarios`) |
| `administradores` | `nombre`, `telefono`, `foto`, `gremio`, `gremioFoto` |
| `conductores_conectados` | `ubicacion{lat, lng}` — posición en tiempo real |

⚠️ `conductor` y `cliente` son colecciones **separadas** de `usuarios`. Verificar cuál aplica antes de leer/escribir.

---

## Filtrado por tipo de vehículo

- `VehicleType` enum: `lib/screens/usuario_cliente/presentacion/model/vehicle_type.dart`
  - `.firestoreKey` → 'carro' | 'moto'
  - `.basePriceDia` / `.basePriceNoche` para cálculo de tarifa
- Conductor ve solo solicitudes de su tipo (`InicioConductorViewModel._buildPendingSolicitudItem`).
- Solicitud guarda `tipoVehiculo` al crearse (`crearSolicitud`).
- Conductores sin `tipoVehiculo` en perfil ven todas (backward compat).

---

## Servicios principales (`lib/core/services/`)

| Clase | Archivo | Propósito |
|-------|---------|-----------|
| `FcmService` | `fcm_service.dart` | Push notifications, token FCM |
| `TrackingService` | `tracking_service.dart` | GPS tracking conductor (foreground) |
| `BackgroundTrackingService` | `background_tracking_service.dart` | GPS segundo plano |
| `NotificacionesServicio` | `notificacion_servicio.dart` | Notificaciones locales, `.instance` |
| `MapServiceAdapter` | `map_service_adapter.dart` | Rutas y polilíneas Google Maps |
| `RouteCacheService` | `route_cache_service.dart` | Caché local de solicitud activa |
| `FirebaseService` | `firebase_service.dart` | CRUD solicitudes y ubicaciones |
| `AuthService` | `auth_service.dart` | Pantalla inicial, gestión de sesión |
| `RideService` | `ride_service.dart` | Lógica de negocio de viaje |
| `UbicacionServicio` | `ubicacion_servicio.dart` | Ubicación del dispositivo |
| `ChatServiceAdapter` | `chat_service_adapter.dart` | Mensajería en viaje |
| `AppRemoteConfigService` | `app_remote_config_service.dart` | Firebase Remote Config |

---

## Sesión activa — triple fuente (riesgo)

```
1. SessionHelper.getActiveSolicitud()        → 'active_solicitud_id'
2. RouteCacheService.getActiveSolicitudId()  → 'route_cache_<id>'
3. SharedPreferences legacy:
   'cliente_solicitud_activa' / 'conductor_solicitud_activa'
```

Al limpiar sesión, borrar las tres. `AuthService.determineInitialScreen()` ya lo hace.

---

## Puntos de entrada de navegación

```
HomeView                  → lib/screens/home_screen.dart
HomeClienteView           → lib/screens/usuario_cliente/presentacion/view/home_cliente_view.dart
InicioConductor           → lib/screens/usuario_conductor/presentacion/view/InicioConductorView.dart
PanelAdministradorScreen  → lib/features/phone_auth/screens/panel_administrador_screen.dart
TripTrackingScreen        → lib/features/trip_tracking_cliente/views/trip_tracking_screen.dart
DriverTripScreen          → lib/features/driver_trip/screens/driver_trip_screen.dart
```

---

## Convenciones

- **MVVM estricto**: View sin lógica de negocio. Estado en `ChangeNotifier` + `Provider`.
- **No setState** en pantallas complejas → usar `notifyListeners()` desde el ViewModel.
- **Archivos**: legacy en español, módulos nuevos en inglés. Clases en PascalCase.
- **Sin comentarios redundantes**: solo el "por qué" cuando no es obvio.
- **ScreenUtil**: base `390×844`. Usar `.w`, `.h`, `.sp`.
- **VehicleType**: `VehicleType.carro` | `VehicleType.moto` → Firestore key: `.firestoreKey` → 'carro'|'moto'.
- **Estado**: siempre `SolicitudEstado.normalize()`.

---

## Riesgos técnicos activos

1. **Arquitectura híbrida**: `screens/` (legacy) + `features/` (moderno). Evitar duplicar lógica; migrar progresivamente.
2. **Listeners en vistas**: algunos listeners de Firestore aún en Views. Al tocar esas pantallas, migrarlos al ViewModel.
3. **Normalización duplicada**: `AuthService._normalizeEstadoCliente()` duplica `SolicitudEstado.normalize()`. No agregar más puntos.
4. **Triple fuente de sesión activa**: ver sección "Sesión activa" antes de leer/escribir solicitud activa.
5. **Colecciones `conductor` vs `usuarios`**: son separadas. Verificar cuál aplica en cada flujo.
