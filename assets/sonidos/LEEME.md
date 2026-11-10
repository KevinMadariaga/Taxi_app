# Sonidos de notificación

Familia Ride: tonos originales (sin audio de terceros), elegidos el 2026-11-10 y
generados con `python3 tool/generar_sonidos.py`. Este WAV es la fuente; las copias que usa la app son:

- Android: `android/app/src/main/res/raw/<nombre>.mp3` (protegidos en `keep.xml`)
- iOS: `ios/Runner/Sonidos/<nombre>.caf` (PCM 16 bits, < 30 s, en Copy Bundle Resources)

Para regenerar desde un WAV nuevo:

    ffmpeg -y -i assets/sonidos/X.wav -c:a libmp3lame -b:a 128k android/app/src/main/res/raw/X.mp3
    afconvert -f caff -d LEI16@44100 assets/sonidos/X.wav ios/Runner/Sonidos/X.caf

Nombres: minúsculas, sin espacios ni guiones (Android lo exige). Cambiar el
sonido de un canal Android exige un canal nuevo (`_v2`), ver
`lib/core/constants/canales_notificacion.dart`.
