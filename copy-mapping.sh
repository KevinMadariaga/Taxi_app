#!/bin/bash
# Script: copy-mapping.sh
# Uso: ./copy-mapping.sh
# Copia el mapping.txt generado tras un build release y lo renombra con el versionCode actual

MAPPING_PATH="android/app/build/outputs/mapping/release/mapping.txt"
GRADLE_FILE="android/app/build.gradle.kts"

if [ ! -f "$MAPPING_PATH" ]; then
  echo "No se encontró mapping.txt. ¿Ya ejecutaste flutter build appbundle --release?"
  exit 1
fi

# Extraer versionCode del build.gradle.kts
VERSION_CODE=$(grep -E 'versionCode\s*=\s*[0-9]+' "$GRADLE_FILE" | grep -o '[0-9]\+')
if [ -z "$VERSION_CODE" ]; then
  echo "No se pudo extraer versionCode de $GRADLE_FILE"
  exit 1
fi

DEST="mapping-v$VERSION_CODE.txt"
cp "$MAPPING_PATH" "$DEST"
echo "mapping.txt copiado como $DEST"
