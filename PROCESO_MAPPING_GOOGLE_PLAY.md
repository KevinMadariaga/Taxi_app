# Proceso para asociar mapping.txt a cada versión en Google Play Console

## 1. Verificar configuración de ofuscación
- Abre `android/app/build.gradle.kts` (o `build.gradle`).
- Asegúrate de que el bloque `release` tenga:

```
buildTypes {
    release {
        minifyEnabled true
        proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
    }
}
```
- R8 es el ofuscador por defecto en versiones recientes.

## 2. Generar el App Bundle y mapping.txt
- Ejecuta:
  ```
  flutter build appbundle --release
  ```
- El archivo `mapping.txt` se generará en:
  `android/app/build/outputs/mapping/release/mapping.txt`

## 3. Subir mapping.txt a Google Play Console
- Accede a Google Play Console > Tu app > Versión 5 (o la que corresponda).
- En la sección "Archivos de desofuscación", sube el `mapping.txt` generado.
- Asegúrate de asociar el archivo a la versión correcta.

## 4. Buenas prácticas
- Renombra y guarda cada mapping.txt con el versionCode correspondiente, por ejemplo: `mapping-v5.txt`.
- No sobrescribas archivos de versiones anteriores.
- Si usas CI/CD, automatiza la copia/backup del mapping.txt tras cada build release.

## 5. Automatización básica (opcional)
Puedes agregar un script post-build en tu pipeline o localmente:

```sh
# Copia el mapping.txt con el versionCode extraído de build.gradle
VERSION_CODE=$(grep versionCode android/app/build.gradle.kts | grep -o '[0-9]\+')
cp android/app/build/outputs/mapping/release/mapping.txt mapping-v$VERSION_CODE.txt
```

## 6. Resultado esperado
- La advertencia de Google Play Console desaparecerá.
- Los reportes de errores y ANR mostrarán trazas legibles.

---

**Documenta este proceso en tu repo y repítelo en cada publicación de versión release.**
