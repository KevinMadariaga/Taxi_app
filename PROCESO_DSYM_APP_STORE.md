# Proceso para asociar archivos .dSYM en App Store Connect

## 1. Ubica los archivos .dSYM
- Tras ejecutar `flutter build ios --release`, los archivos .dSYM se generan en:
  - `build/ios/Release-iphoneos/Runner.app.dSYM`
  - (También pueden generarse: `App.framework.dSYM`, `Flutter.framework.dSYM`, etc.)

## 2. Empaqueta el .dSYM en un zip
Desde la raíz del proyecto ejecuta:

```sh
cd build/ios/Release-iphoneos
zip -r Runner.app.dSYM.zip Runner.app.dSYM
```

## 3. Sube el .dSYM a App Store Connect
- Ve a [App Store Connect](https://appstoreconnect.apple.com/) > Tu app > Actividad > Builds.
- Selecciona el build correspondiente.
- En “Archivos de símbolos de depuración” (Debug Symbols), sube el archivo `Runner.app.dSYM.zip`.

## 4. Valida
- App Store Connect procesará el archivo y los crash reports mostrarán trazas legibles.

## Buenas prácticas
- Guarda cada .dSYM por versión/build (no sobrescribas).
- Si usas Crashlytics, también puedes subirlos con el script de Firebase.
- Documenta este proceso para futuras publicaciones.

---

**Repite este proceso en cada build release para asegurar la trazabilidad de errores en producción.**
