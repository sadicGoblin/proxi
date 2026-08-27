# Proxi nativa (Flutter)

La app Android/iOS **de verdad** — código propio, independiente de la web.
Comparte con ella solo la base de datos (Firestore `proxi-live`), así que un
grupo puede mezclar gente en `proxi-live.web.app` y en esta app: mismos códigos
de sala, mismos miembros, misma junta.

## Su razón de existir (lo que la web no puede)

- ✅ **Ubicación en segundo plano** (ya implementado): al entrar a un grupo se
  levanta un servicio en primer plano (notificación persistente estilo Google
  Maps) y tu posición se sigue compartiendo **con la pantalla bloqueada** o con
  la app minimizada. Al salir del grupo, se apaga y tu posición se borra.
- 🔜 Notificaciones: "movieron la junta", "X llegó al punto".
- 🔜 Geofencing de llegada, modo ahorro de batería, perfil con foto.

## Correr y compilar

```bash
cd app_nativa
flutter run                 # con un teléfono conectado (USB) o emulador
flutter build apk --release # APK en build/app/outputs/flutter-apk/app-release.apk
```

Solo Android/iOS (las carpetas de escritorio se quitaron para no requerir el
Modo de desarrollador de Windows).

## Estado / pendientes técnicos

- Firebase se inicializa con opciones manuales (la misma config pública de la
  web, en `lib/core.dart`). Funciona para auth anónima y Firestore. Para
  Google Sign-In nativo y notificaciones push hay que **registrar la app
  Android en la consola de Firebase** (`flutterfire configure`) — eso genera
  opciones propias y pide la huella SHA-1/SHA-256 de la firma.
- Release firmado con la llave debug por defecto; antes de distribuir en serio,
  configurar firma propia en `android/app/build.gradle.kts` (ver
  `twa/README.md` para el patrón keystore.properties).
- La presencia escribe el mismo esquema que la web y cumple `firestore.rules`
  (name/photo/lat/lng/acc/precise/ts/t/expireAt con TTL de 1 h).
- Pantallas: Home (nombre, entrar/crear grupo, recientes) y Sala (mapa OSM con
  rotación de 2 dedos, grupo en vivo con "hace X min", bandera de la junta,
  distancia al punto, seguir/centrarme). La junta se edita por ahora desde la
  web; la edición nativa viene en la próxima ronda.

## Estructura

| Archivo | Qué hace |
|---|---|
| `lib/core.dart` | Firebase + identidad anónima, nombre, grupos recientes, constantes de frescura |
| `lib/main.dart` | Tema oscuro Proxi + pantalla de inicio |
| `lib/sala_screen.dart` | Mapa en vivo, presencia con servicio en primer plano, junta y distancias |
