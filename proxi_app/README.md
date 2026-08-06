# Proxi App (Flutter)

App móvil de Proxi. Dos formas de resolver el "metro final":
- **Proxi Faro** ⭐ (funciona en CUALQUIER teléfono) — la otra persona **destella un color único**
  (flash + pantalla) y tú la encuentras con la vista. Ver [`../FARO.md`](../FARO.md).
- **UWB** (solo gama alta) — distancia ±10 cm entre dos chips UWB. Ver [`../UWB.md`](../UWB.md).

Más: mapa satélite + ubicación en vivo por Firebase (proyecto `proxi-live`, sala `"prueba"`).

**APK listo para compartir:** [`../Proxi-Faro.apk`](../Proxi-Faro.apk) (release, 44 MB).

---

## Cómo probar Proxi Faro (con 2 teléfonos, cualquiera)

1. Instala el APK en **ambos** teléfonos (envíalo por WhatsApp/USB; activa "instalar apps
   desconocidas"). Sirve tu **S25 y tu Vivo V25** — Faro no necesita UWB.
2. Abre la app en los dos: entran a la sala `"prueba"` y se ven en el mapa.
3. En un teléfono pulsa **"Pídele que se ilumine"** → el **otro teléfono destella en cian**
   (flash LED + pantalla, patrón de 3 parpadeos) y muestra "TE ESTÁN BUSCANDO".
4. El que busca ve *"busca el destello CIAN"* y, al hallarlo, pulsa **"¡Lo veo!"** → se apaga.

> El **flash LED** solo enciende en teléfonos físicos (el emulador solo hace parpadear la
> pantalla). En tu S25/Vivo verás LED + pantalla.

**Aún NO incluido (siguiente incremento):** la capa BLE "caliente/frío" (rumbo por gradiente) y
la capa de rumbo AR. Este MVP valida el mecanismo estrella: la **baliza óptica**.

---

## Qué hace

- Muestra un **mapa satélite** (Esri, sin API key) con los miembros de la sala.
- Comparte tu ubicación **en vivo** por Firebase (proyecto `proxi-live`, sala fija `"prueba"`).
- Si **ambos** teléfonos tienen **UWB**, se emparejan (intercambian parámetros por Firestore) y
  muestran **distancia ±10 cm + flecha** hacia el otro. Si no, cae a **GPS**.

## Requisitos para probar el UWB

1. **DOS teléfonos con chip UWB.** Ej.: Samsung S25 (verifica: *Ajustes → busca "UWB"*), otro
   Samsung +/Ultra, o Pixel 6 Pro+. ⚠️ El **Vivo V25 no tiene UWB** → con él verás solo GPS.
2. **Android 12+ (API 31)** en ambos.
3. Conceder los permisos de **ubicación** y **UWB** cuando la app los pida.

## Cómo correrlo

```bash
cd proxi_app
flutter pub get
flutter devices           # confirma que ves tus teléfonos
flutter run -d <id>       # instala en un teléfono; repite en el otro
```

- Si `flutter run` se queja del JDK: usa el que trae Android Studio →
  `flutter config --jdk-dir "/Applications/Android Studio.app/Contents/jbr/Contents/Home"`
  (tienes Java 8 en el PATH; Gradle necesita 17, que Android Studio ya incluye).
- Abre la app en **los dos teléfonos**: entran solos a la sala `"prueba"` y se ven en el mapa.
  Con UWB en ambos, el panel inferior pasa de **"metros · GPS"** a **"metros · UWB"** (±10 cm).

## Estructura

```
lib/
  main.dart                  UI, mapa, miembros en vivo, orquestación del emparejamiento UWB
  services/uwb_service.dart  Puente Dart <-> nativo (MethodChannel/EventChannel)
android/app/src/main/kotlin/.../MainActivity.kt
                             Modulo UWB nativo (Jetpack androidx.core.uwb)  <- la parte a iterar
android/app/google-services.json   Config de Firebase (Android)
```

## Cómo funciona el emparejamiento UWB

UWB no descubre solo al otro teléfono; necesita intercambiar parámetros por otro canal.
**Ese canal es Firestore** (`salas/prueba/pair/session`):

1. El teléfono con `uid` menor es **controller**; el otro, **controlee**.
2. Controller publica su dirección + canal + `sessionId` + `sessionKey`; controlee publica su dirección.
3. Cuando cada uno tiene los datos del otro, ambos llaman `startRanging` y llegan las lecturas
   `RangingResult` (distancia + ángulo) por el `EventChannel`.

## Lo que hay que iterar sobre el hardware

- **`MainActivity.kt`** usa `androidx.core.uwb:uwb:1.0.0` (estable). Si algún nombre de la API
  cambia en futuras versiones (`RangingParameters`, `UwbComplexChannel`,
  `RangingResult.RangingResultPosition`, `CONFIG_UNICAST_DS_TWR`), este archivo es el único que
  ajustarías. La lógica de ranging conviene afinarla contra tus equipos reales.
- El **ángulo (azimuth)** viene relativo a cómo apunta el teléfono, así que la flecha "gira hacia el
  otro" al mover el equipo. Ideal para el modo "camina siguiendo la flecha".

## Notas honestas

- **iOS:** falta configurar Xcode/CocoaPods; en iOS el equivalente es *Nearby Interaction* (otro
  archivo nativo). Por ahora el proyecto apunta a **Android**.
- **Interop iOS<->Android por UWB** aún no es plug-and-play (estándar FiRa). Asumir iPhone<->iPhone y
  Android<->Android.
- **Seguridad:** la sala y las reglas de Firestore están **abiertas solo para la prueba**
  (`../firestore.rules`). Cerrar antes de producción (ver [`../MODELO-NEGOCIO.md`](../MODELO-NEGOCIO.md) §6).
- **Fallback universal:** para equipos sin UWB (mucha gama media en LatAm), la siguiente capa es
  Bluetooth "caliente/frío", aún no incluida en este MVP.
