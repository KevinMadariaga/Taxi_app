#!/usr/bin/env bash
#
# init.sh — Inicialización del entorno de desarrollo
# App móvil de transporte (Flutter + Firebase + Google Maps)
#
# Uso:
#   ./init.sh
#
# Este script deja el proyecto listo para trabajar:
#   - Verifica las herramientas necesarias (Flutter, Dart, Git).
#   - Instala dependencias.
#   - Prepara la configuración de secretos (sin commitearlos).
#   - Verifica que no haya claves/secretos expuestos en el repo.
#   - Corre los chequeos de calidad (format, analyze, test).
#   - Instala un git hook de pre-commit con los chequeos obligatorios.
#
# Las reglas de este proyecto están en AGENTS.md. Léelo.

set -euo pipefail

# ----------------------------------------------------------------------------
# Colores y helpers de log
# ----------------------------------------------------------------------------
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
SIN_COLOR='\033[0m'

info()    { echo -e "${AZUL}ℹ ${SIN_COLOR}$1"; }
ok()      { echo -e "${VERDE}✔ ${SIN_COLOR}$1"; }
aviso()   { echo -e "${AMARILLO}⚠ ${SIN_COLOR}$1"; }
error()   { echo -e "${ROJO}✖ ${SIN_COLOR}$1"; }
titulo()  { echo -e "\n${AZUL}== $1 ==${SIN_COLOR}"; }

# Verifica que un comando exista
requiere() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "No se encontró '$1'. Instálalo antes de continuar."
    return 1
  fi
}

# ----------------------------------------------------------------------------
# 0. Ubicarse en la raíz del proyecto
# ----------------------------------------------------------------------------
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ"

echo -e "${AZUL}"
echo "┌────────────────────────────────────────────────┐"
echo "│   Inicializando entorno — App de Transporte     │"
echo "│   Flutter · Firebase · Google Maps              │"
echo "└────────────────────────────────────────────────┘"
echo -e "${SIN_COLOR}"

# ----------------------------------------------------------------------------
# 1. Verificar herramientas necesarias
# ----------------------------------------------------------------------------
titulo "1. Verificando herramientas"

FALTA=0
requiere flutter || FALTA=1
requiere dart    || FALTA=1
requiere git     || FALTA=1

if [ "$FALTA" -eq 1 ]; then
  error "Faltan herramientas requeridas. Aborta."
  exit 1
fi

# Versión de Flutter (informativa)
VERSION_FLUTTER="$(flutter --version 2>/dev/null | head -n 1 || echo 'desconocida')"
ok "Flutter detectado: $VERSION_FLUTTER"
ok "Git detectado:     $(git --version)"

# Firebase CLI y FlutterFire (recomendados, no obligatorios)
if command -v firebase >/dev/null 2>&1; then
  ok "Firebase CLI detectado."
else
  aviso "Firebase CLI no encontrado. Recomendado para reglas y despliegue."
  aviso "  Instálalo con: npm install -g firebase-tools"
fi

if command -v flutterfire >/dev/null 2>&1; then
  ok "FlutterFire CLI detectado."
else
  aviso "FlutterFire CLI no encontrado. Útil para configurar Firebase."
  aviso "  Instálalo con: dart pub global activate flutterfire_cli"
fi

# ----------------------------------------------------------------------------
# 2. Instalar dependencias
# ----------------------------------------------------------------------------
titulo "2. Instalando dependencias"

flutter pub get
ok "Dependencias instaladas (flutter pub get)."

# ----------------------------------------------------------------------------
# 3. Preparar configuración de secretos
# ----------------------------------------------------------------------------
titulo "3. Configuración de secretos"

# Plantilla de variables de entorno para --dart-define
if [ ! -f ".env.example" ]; then
  cat > .env.example <<'EOF'
# Plantilla de variables de entorno.
# Copia este archivo a .env y rellena los valores reales.
# NUNCA commitees .env (debe estar en .gitignore).
#
# Se inyectan en la app con --dart-define-from-file=.env
# Ejemplo: flutter run --dart-define-from-file=.env

GOOGLE_MAPS_API_KEY_ANDROID=
GOOGLE_MAPS_API_KEY_IOS=
EOF
  ok "Creado .env.example (plantilla de secretos)."
else
  info ".env.example ya existe, se respeta."
fi

if [ ! -f ".env" ]; then
  cp .env.example .env
  aviso "Creado .env a partir de la plantilla. RELLENA los valores reales."
else
  ok ".env ya existe."
fi

# Asegurar que los secretos están en .gitignore
asegurar_gitignore() {
  local patron="$1"
  if [ ! -f .gitignore ] || ! grep -qxF "$patron" .gitignore; then
    echo "$patron" >> .gitignore
    ok "Añadido a .gitignore: $patron"
  fi
}

touch .gitignore
asegurar_gitignore ".env"
asegurar_gitignore "*.env"
asegurar_gitignore "google-services.json"
asegurar_gitignore "GoogleService-Info.plist"
asegurar_gitignore "lib/firebase_options.dart"
asegurar_gitignore "*.keystore"
asegurar_gitignore "*.jks"
asegurar_gitignore "key.properties"

# ----------------------------------------------------------------------------
# 4. Verificar que no haya secretos expuestos en el repo
# ----------------------------------------------------------------------------
titulo "4. Auditoría de secretos"

# Archivos sensibles que NO deberían estar trackeados por git
SENSIBLES=("google-services.json" "GoogleService-Info.plist" ".env" "key.properties")
EXPUESTO=0

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for archivo in "${SENSIBLES[@]}"; do
    if git ls-files --error-unmatch "$archivo" >/dev/null 2>&1; then
      error "¡'$archivo' está trackeado por git! Sácalo: git rm --cached $archivo"
      EXPUESTO=1
    fi
  done

  # Búsqueda básica de API keys de Google hardcodeadas (patrón AIza...)
  if git grep -nIE "AIza[0-9A-Za-z_-]{35}" -- '*.dart' '*.kt' '*.swift' >/dev/null 2>&1; then
    error "Posible API key de Google hardcodeada en el código (patrón AIza...)."
    error "Muévela a --dart-define / variables de entorno. Ver AGENTS.md §7."
    EXPUESTO=1
  fi

  if [ "$EXPUESTO" -eq 0 ]; then
    ok "No se detectaron secretos expuestos."
  else
    aviso "Se detectaron posibles secretos. Revísalo ANTES de continuar (AGENTS.md §7,§9)."
  fi
else
  aviso "Esto no es un repo git todavía. Inicialízalo con: git init"
fi

# ----------------------------------------------------------------------------
# 5. Recordatorio de firestore.rules (tarea crítica pendiente)
# ----------------------------------------------------------------------------
titulo "5. Reglas de seguridad de Firestore"

if [ ! -f "firestore.rules" ]; then
  aviso "🔴 NO existe firestore.rules — TAREA CRÍTICA antes de producción."
  aviso "   Sin reglas, cualquiera podría leer ubicaciones y chats de otros."
  aviso "   Ver checklist en AGENTS.md §7 y §11."
else
  ok "firestore.rules existe."
fi

# ----------------------------------------------------------------------------
# 6. Chequeos de calidad
# ----------------------------------------------------------------------------
titulo "6. Chequeos de calidad"

info "Formateando código (dart format)..."
dart format . >/dev/null && ok "Formato aplicado."

info "Analizando código (flutter analyze)..."
if flutter analyze; then
  ok "flutter analyze limpio."
else
  aviso "flutter analyze reportó problemas. Revísalos."
fi

info "Corriendo tests (flutter test)..."
if flutter test; then
  ok "Tests pasaron."
else
  aviso "Hay tests fallando o aún no hay tests. Recuerda: todo cambio nuevo lleva tests (AGENTS.md §6)."
fi

# ----------------------------------------------------------------------------
# 7. Instalar git hook de pre-commit
# ----------------------------------------------------------------------------
titulo "7. Git hook de pre-commit"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HOOK=".git/hooks/pre-commit"
  cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Pre-commit hook — chequeos obligatorios antes de cada commit.
# Ver AGENTS.md.
set -e

echo "→ Verificando formato..."
if ! dart format --output=none --set-exit-if-changed . ; then
  echo "✖ Hay archivos sin formatear. Corre: dart format ."
  exit 1
fi

echo "→ Analizando código..."
if ! flutter analyze ; then
  echo "✖ flutter analyze falló. Corrige los errores antes de commitear."
  exit 1
fi

# Bloquear secretos comunes en el staging
if git diff --cached --name-only | grep -E '(\.env$|google-services\.json|GoogleService-Info\.plist|key\.properties)' >/dev/null 2>&1; then
  echo "✖ Estás intentando commitear un archivo de secretos. Abortado."
  exit 1
fi

if git diff --cached -U0 | grep -E 'AIza[0-9A-Za-z_-]{35}' >/dev/null 2>&1; then
  echo "✖ Posible API key de Google en el cambio. Muévela a variables de entorno."
  exit 1
fi

echo "✔ Chequeos de pre-commit OK."
EOF
  chmod +x "$HOOK"
  ok "Instalado git hook de pre-commit (.git/hooks/pre-commit)."
else
  aviso "No es un repo git; se omite la instalación del hook."
fi

# ----------------------------------------------------------------------------
# Fin
# ----------------------------------------------------------------------------
titulo "Listo"
ok "Entorno inicializado."
echo ""
info "Próximos pasos:"
echo "   1. Rellena .env con tus claves reales (Google Maps)."
echo "   2. Configura Firebase (flutterfire configure) si aún no lo está."
echo "   3. 🔴 Escribe firestore.rules (crítico — ver AGENTS.md §7)."
echo "   4. Corre la app:  flutter run --dart-define-from-file=.env"
echo ""
