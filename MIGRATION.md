# Migración: centralizar servicios en `lib/core/services`

Fecha: 19 de marzo de 2026

Resumen
-------
Esta migración realiza un traslado controlado y no destructivo de los servicios globales hacia la carpeta canónica `lib/core/services`. El objetivo es facilitar una transición a Clean Architecture + MVVM, mantener compatibilidad mientras se migran consumidores y reducir duplicidad.

Principales decisiones
- Estratégia: migración por lotes no destructiva (adapter/shim → reemplazo → eliminación).
- Surface canónica: `lib/core/services` (agregador en `core/services/services.dart`).
- Compatibilidad: adaptadores de compatibilidad (`map_service_adapter.dart`, `chat_service_adapter.dart`) expusieron APIs legacy mientras se actualizaban los consumidores.

Qué se cambió (alto nivel)
- Añadidos (implementaciones/infra):
  - `lib/core/services/google_sign_in_service.dart` (nuevo, canonical)
  - `lib/core/services/chat_firestore_datasource.dart` (nuevo, canonical)

- Adaptadores / agregador existentes (ya presentes o añadidos durante la migración):
  - `lib/core/services/map_service_adapter.dart`
  - `lib/core/services/chat_service_adapter.dart`
  - `lib/core/services/services.dart` (exportador central)

- Archivos eliminados (shims movidos o retirados de `lib/services`):
  - `lib/services/auth_service.dart` (re-export)
  - `lib/services/background_tracking_service.dart` (re-export)
  - `lib/services/firebase_service.dart` (re-export)
  - `lib/services/notificacion_servicio.dart` (re-export)
  - `lib/services/tracking_service.dart` (re-export)
  - `lib/services/solicitud_firestore_datasource.dart` (duplicado)
  - `lib/services/chat_service.dart`
  - `lib/services/map_service.dart`
  - `lib/services/DireccionesServicio.dart`
  - `lib/services/chat_firestore_datasource.dart`
  - `lib/services/google_sign_in_service.dart`

Nota: tras estas acciones la carpeta `lib/services/` quedó vacía; el código ahora importa las implementaciones canónicas en `lib/core/services/` o los adaptadores cuando era necesario.

Archivos actualizados (ejemplos representativos)
- `lib/screens/usuario_cliente/presentacion/viewmodels/ruta_cliente_viewmodel.dart` — import a `chat_service_adapter` y `map_service_adapter`.
- `lib/screens/usuario_conductor/presentacion/view/RutaDestinoView.dart` — reemplazo de `DireccionesServicio` por `MapService.getRoutePolyline` (adapter).
- `lib/features/trip_tracking_cliente/services/chat_service.dart` — ahora importa `core/services/chat_firestore_datasource.dart`.
- `lib/components/google_sign_in_button.dart` y `lib/screens/register_screen.dart` — ahora usan `core/services/google_sign_in_service.dart`.
- `lib/core/services/services.dart` — actualizados exports a implementaciones core.

Por qué así (racional)
- Minimizar ruptura: mantener shims/adaptadores reduce riesgo cuando las APIs feature divergen.
- Permitir migración por características: los equipos pueden migrar vistas/viewmodels por lotes y validar con tests.
- Centralizar surface: facilita documentación, DI y pruebas.

Checklist y pasos para eliminar un shim de forma segura (procedimiento recomendado para siguientes lotes)
1. Buscar todos los imports del shim: `grep -R "package:taxi_app/services/NAME" -n`.
2. Reemplazar imports por: (a) `package:taxi_app/core/services/NAME.dart` si existe, o (b) `package:taxi_app/core/services/NAME_adapter.dart`.
3. Ejecutar análisis estático: `flutter analyze`.
4. Ejecutar tests unitarios: `flutter test --no-pub`.
5. Si todo pasa, eliminar el archivo shim y repetir `analyze` + `test`.

Comandos útiles (copiar/pegar)
```bash
# analizar
flutter analyze

# tests (rápido, sin pub ya que dependencias están resueltas en CI local)
flutter test --no-pub

# crear branch y commit
git checkout -b feat/migrate-services-core
git add .
git commit -m "feat(migration): centralizar servicios en lib/core/services (lote X)"
git push -u origin feat/migrate-services-core
``` 

Revisión / PR
- Añadir este `MIGRATION.md` al PR.
- Incluir en la descripción del PR: lista de archivos eliminados, pasos de verificación y lista de cambios en consumers importantes (pantallas + viewmodels).
- Ejecutar `flutter analyze` y `flutter test` en CI antes de aprobar.

Rollback rápido
- Para deshacer cambios locales: `git checkout -- <path>` o `git restore <file>`.
- Para revertir un commit ya empujado: `git revert <commit>` y abrir PR con la reversión.

Próximos pasos recomendados
- Limpiar warnings e `info` del analizador en adaptadores.
- Documentar la política de servicios (dónde crear nuevos servicios: `lib/core/services`).
- Automatizar una verificación de imports (script que busque `package:taxi_app/services/` y falle la build si hay matches tras la migración final).

Contacto / autor
- Autor: Copilote de migración (automático) — correlación de cambios con tests locales.

Fin del documento
