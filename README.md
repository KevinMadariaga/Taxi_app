# Taxi Ya

Aplicación móvil de transporte tipo taxi construida con Flutter, con geolocalización en tiempo real para cliente y conductor, autenticación multi-método y operación basada en Firebase.

## Tabla de contenidos

1. [Descripción del proyecto](#descripción-del-proyecto)
2. [Características principales](#características-principales)
3. [Arquitectura](#arquitectura)
4. [Estructura del proyecto](#estructura-del-proyecto)
5. [Flujo funcional de la app](#flujo-funcional-de-la-app)
6. [Stack tecnológico](#stack-tecnológico)
7. [Configuración de entorno](#configuración-de-entorno)
8. [Ejecución local](#ejecución-local)
9. [Build y publicación](#build-y-publicación)
10. [Pruebas](#pruebas)
11. [Riesgos técnicos y mejoras sugeridas](#riesgos-técnicos-y-mejoras-sugeridas)

## Descripción del proyecto

Taxi Ya permite:

- Registro e inicio de sesión de usuarios (cliente, conductor y administrador en flujo específico).
- Creación de solicitudes de viaje desde cliente.
- Asignación y seguimiento de conductor en tiempo real.
- Chat cliente-conductor por solicitud.
- Persistencia de sesión y restauración de flujo activo tras reinicio de la app.

Punto de entrada principal: `lib/main.dart`.

## Características principales

- Autenticación con Google, Apple y OTP por teléfono.
- Gestión de sesión con `SharedPreferences` y Firebase Auth.
- Tracking GPS en foreground y background (conductor).
- Integración con Google Maps y cálculo de rutas/ETA.
- Notificaciones push (FCM) y notificaciones locales.
- Soporte para actualización mínima obligatoria/opcional mediante Remote Config.

## Arquitectura

El proyecto implementa una arquitectura híbrida con orientación MVVM:

- Capa moderna: `core` + `domain` + `data` + `presentation` + `features`.
- Capa legacy aún activa: `screens` y `models`.
- Gestión de estado: `Provider` + `ChangeNotifier`.

### Flujo MVVM aplicado

El flujo operacional sigue este patrón:

`View -> ViewModel/Controller -> UseCase/Repository/Service -> Firebase/API -> respuesta -> notifyListeners -> View`

### Estado actual

- Existe una separación de responsabilidades funcional en módulos nuevos.
- Persisten flujos legacy donde UI y lógica de infraestructura conviven.
- El proyecto se encuentra en transición progresiva hacia estructura modular por features.

## Estructura del proyecto

Resumen de carpetas de `lib/`:

- `core/`: infraestructura transversal (auth service, tracking, FCM, constants, theme, validators).
- `domain/`: entidades, contratos de repositorio y casos de uso.
- `data/`: datasources y repositorios concretos.
- `presentation/`: pantallas/controladores/viewmodels de flujos nuevos (splash, auth, login).
- `features/`: módulos por dominio (`trip_tracking_cliente`, `driver_trip`, `phone_auth`, etc.).
- `screens/`: flujos legacy de cliente y conductor aún productivos.
- `widgets/`: componentes UI reutilizables.
- `helper/`: utilidades transversales (firebase init, permisos, sesión).
- `routes/`: generación de rutas.

## Flujo funcional de la app

1. La app inicializa Firebase, permisos, notificaciones y servicios base.
2. En splash se valida actualización disponible/obligatoria.
3. Se resuelve pantalla inicial según sesión, rol y solicitud activa.
4. Cliente crea solicitud de viaje.
5. El sistema escucha cambios de estado (`buscando`, `asignado`, `en camino`, `en ruta`, `completado`, `cancelado`).
6. Cliente y conductor sincronizan ubicación en tiempo real.
7. Al completar/cancelar, se limpia caché de solicitud y estado de sesión asociado.

## Stack tecnológico

### Framework y estado

- Flutter / Dart
- Provider

### Backend y servicios

- Firebase Core
- Firebase Auth
- Cloud Firestore
- Firebase Messaging
- Firebase Storage
- Firebase Crashlytics
- Firebase Analytics
- Firebase Remote Config
- Firebase App Check

### Geolocalización y mapas

- google_maps_flutter
- geolocator
- geocoding
- flutter_background_service

### UI y utilidades

- flutter_screenutil
- cached_network_image
- lottie
- flutter_local_notifications
- shared_preferences
- http

## Configuración de entorno

### Requisitos

- Flutter SDK compatible con `sdk: ^3.10.7`
- Xcode (iOS) y Android Studio/SDK (Android)
- Proyecto Firebase configurado para Android/iOS

### Variables y archivos clave

- `lib/firebase_options.dart`
- `android/local.properties` o `android/gradle.properties` para `MAPS_API_KEY`
- `android/key.properties` (basado en `android/key.properties.example`) para firma release Android

## Ejecución local

```bash
flutter pub get
flutter run
```

Opcional para QA de autenticación telefónica (solo no release):

```bash
flutter run --dart-define=PHONE_AUTH_TEST_MODE=true
```

## Build y publicación

### Android App Bundle (Google Play)

1. Crea la llave de subida (una sola vez):

```bash
keytool -genkeypair -v \
  -keystore android/keystore/taxiapp-upload-key.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias taxiapp
```

2. Crea `android/key.properties` a partir de `android/key.properties.example`.

3. Configura `MAPS_API_KEY` en:

- `android/local.properties` (local)
- `android/gradle.properties`
- variable de entorno `MAPS_API_KEY`

4. Genera el bundle:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Salida:

`build/app/outputs/bundle/release/app-release.aab`

### Mapping de desofuscación (Android)

Después del build release:

```bash
./copy-mapping.sh
```

Esto copia `mapping.txt` y lo renombra a `mapping-vX.txt` según `versionCode`.

Sube ese archivo en Google Play Console para trazabilidad de crash/ANR.

Referencia: `PROCESO_MAPPING_GOOGLE_PLAY.md`.

### dSYM para iOS (App Store)

1. Build iOS release:

```bash
flutter build ios --release
```

2. Empaquetar dSYM:

```bash
cd build/ios/Release-iphoneos
zip -r Runner.app.dSYM.zip Runner.app.dSYM
```

3. Subir `Runner.app.dSYM.zip` en App Store Connect.

Referencia: `PROCESO_DSYM_APP_STORE.md`.

## Pruebas

El repositorio incluye pruebas en `test/` para componentes, modelos, servicios, pantallas y sesión.

Ejecución:

```bash
flutter test
```

## Riesgos técnicos y mejoras sugeridas

- Consolidar arquitectura en una sola línea (features modernas) y reducir dependencia de flujos legacy.
- Extraer listeners de Firestore desde vistas hacia ViewModels/controladores.
- Unificar normalización/máquina de estados de solicitud en un solo módulo de dominio.
- Evitar claves sensibles embebidas en código fuente; moverlas a configuración segura.
- Completar o remover carpetas vacías para mejorar claridad de mantenimiento.

---

Si necesitas, puedo convertir este README también en una versión bilingüe (ES/EN) o preparar una guía separada de onboarding para nuevos desarrolladores.