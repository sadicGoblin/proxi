# Proxi — APK Android (TWA)

APK real de Android que abre **la misma web** (https://proxi-live.web.app) como
Trusted Web Activity: pantalla completa dentro de Chrome, así **todo funciona
igual** (GPS, Google Sign-In, compartir, rutas) y la app **se actualiza sola**
con cada `firebase deploy` — sin recompilar ni redistribuir el APK.

## Compilar

Requisitos ya presentes en esta máquina: JDK 17, Android SDK (en
`%LOCALAPPDATA%\Android\Sdk`, apuntado por `local.properties`) y Gradle 8.14
(cacheado en `~\.gradle\wrapper\dists`).

```bash
cd twa
gradle assembleRelease
# APK firmado: app/build/outputs/apk/release/app-release.apk
```

Para publicar una nueva versión del APK: sube `versionCode`/`versionName` en
`app/build.gradle`, compila y copia el APK a `public/proxi.apk` de la web.

## Firma (¡IMPORTANTE!)

- `proxi.keystore` + `keystore.properties` **no van a git** (ver `.gitignore`).
- **Respáldalos** (Drive/pendrive): si se pierden, no se puede actualizar la app
  instalada — Android exige la misma firma para actualizar.
- La huella SHA-256 de esta llave está publicada en
  `public/.well-known/assetlinks.json`; con eso Android verifica el dominio y
  la app abre **sin barra de URL**. Si algún día regeneras el keystore, hay que
  actualizar ese archivo y volver a desplegar la web.

SHA-256 actual:
`96:A6:7E:2A:88:BD:D5:03:FB:14:0A:BE:95:54:A1:5A:3B:22:69:7F:51:2C:CD:20:A3:F3:98:20:35:2E:AA:3D`

## Detalles

- Paquete: `cl.favric.proxi` · minSdk 21 (Android 5+) · target/compile SDK 35.
- Los links `https://proxi-live.web.app/...` abren directo en la app
  (intent-filter con `autoVerify`).
- Requiere Chrome en el teléfono (si no está, cae a un custom tab del navegador
  disponible). Peso del APK: ~1 MB.
- Este APK **no** agrega ubicación en segundo plano (es la web dentro de
  Chrome). Para eso está el proyecto Flutter (`proxi_app/`) como fase siguiente.
