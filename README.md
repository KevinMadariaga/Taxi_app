# taxi_app

Proyecto de servicio de transporte de taxi. 

## Build Android App Bundle (Google Play)

1. Crea la llave de subida (upload key) una sola vez:

```bash
keytool -genkeypair -v \
	-keystore android/keystore/taxiapp-upload-key.jks \
	-storetype JKS \
	-keyalg RSA -keysize 2048 -validity 10000 \
	-alias taxiapp
```

2. Crea el archivo `android/key.properties` basado en `android/key.properties.example`.

3. Configura `MAPS_API_KEY` para Android release en una de estas opciones:
- `android/local.properties` (solo local)
- `android/gradle.properties`
- Variable de entorno `MAPS_API_KEY`

4. Genera el App Bundle:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

5. El archivo generado queda en:

```text
build/app/outputs/bundle/release/app-release.aab
```

## Guardar y asociar mapping.txt (desofuscación)

Para cumplir con Google Play Console y facilitar el análisis de errores y ANR:

1. Tras generar el App Bundle, ejecuta:

   ```bash
   ./copy-mapping.sh
   ```
   Esto copiará el archivo `mapping.txt` generado en `android/app/build/outputs/mapping/release/` y lo renombrará como `mapping-vX.txt` (donde X es el versionCode actual).

2. Sube el archivo `mapping-vX.txt` a Google Play Console en la sección "Archivos de desofuscación" de la versión correspondiente.

**Recomendaciones:**
- Guarda cada mapping.txt por versión (no sobrescribas).
- Documenta este proceso para futuras publicaciones.
- Si usas CI/CD, automatiza este paso tras cada build release.

Más detalles en el archivo `PROCESO_MAPPING_GOOGLE_PLAY.md`.

## Guardar y asociar archivos .dSYM (iOS)

Para asegurar la trazabilidad de errores en App Store Connect:

1. Tras ejecutar el build release de iOS:
   ```bash
   flutter build ios --release
   ```
2. Empaqueta el archivo .dSYM:
   ```bash
   cd build/ios/Release-iphoneos
   zip -r Runner.app.dSYM.zip Runner.app.dSYM
   ```
3. Sube `Runner.app.dSYM.zip` a App Store Connect en la sección "Debug Symbols" del build correspondiente.

Más detalles en el archivo `PROCESO_DSYM_APP_STORE.md`.