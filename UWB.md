# Proxi — UWB y el "metro final" (Fase 2, app nativa)

> Cómo hacer que dos personas juntas se vean **a ~10 cm** en vez de a 6,5 m (el techo del GPS
> que viste en la prueba). Documento separado de [`PLAN.md`](PLAN.md).

_Escrito a partir de la prueba lado-a-lado del 2026-07-05. Verificar listas de dispositivos y la
interoperabilidad iOS↔Android actuales antes de comprometerlos en una presentación._

---

## 1. Qué es UWB

**Ultra-Wideband** es una radio de pulsos muy cortos (banda ~6-8 GHz). Sirve para medir, **entre
dos dispositivos**, dos cosas en tiempo real:

- **Distancia** (por *tiempo de vuelo* del pulso): precisión **~10 cm**.
- **Dirección** (por *ángulo de llegada*, con varias antenas): una flecha hacia el otro, ±pocos grados.

Diferencia clave con el GPS: el GPS calcula la posición de **cada uno** contra satélites (±5-15 m,
errores independientes → no se fusionan). UWB mide la **relación entre los dos teléfonos**
directamente → por eso sí sabe que están juntos. Es la tecnología del "Precision Finding" del AirTag.

- **Alcance:** ~10-50 m con línea de vista; baja con obstáculos y cuerpos.
- **Requisito:** **ambos** teléfonos con chip UWB **y** la app instalada.

---

## 2. Por qué tiene que ser "en nativo"

El navegador **no** puede acceder al chip UWB (ni a Bluetooth de forma continua). UWB solo se usa
desde una **app nativa**:

- **iOS:** framework **Nearby Interaction** (iOS 14+). Chip **U1** en iPhone 11+ y **U2** en
  iPhone 15+ (más alcance). Da `distance` y `direction` en vivo.
- **Android:** librería **Jetpack UWB** (`androidx.core.uwb`, Android 12+ en hardware compatible).

---

## 3. Cómo funciona el flujo (y cómo encaja con lo que YA tienes)

La gran ventaja: **Proxi ya tiene el canal que UWB necesita** para arrancar. UWB no descubre solo
al otro teléfono; necesita un "canal fuera de banda" para que ambos intercambien un *token* de
emparejamiento. **Ese canal es tu sala de Firebase.**

```
1. GPS + mapa (lo que ya tienes)  →  te acerca a ~10-30 m y te dice quién es quién.
2. Ambos en la misma sala de Firebase  →  intercambian su token UWB por Firestore.
3. Cuando están en rango y ambos tienen UWB  →  se activa el "metro final":
   distancia ±10 cm + flecha exacta, sin depender del GPS ni de la red.
```

- **iOS:** cada teléfono crea un `NIDiscoveryToken`, lo publica en la sala (Firestore), el otro lo
  lee y llama `NISession.run(NINearbyPeerConfiguration(peerToken:))`. Las lecturas llegan solas.
- **Android:** roles *Controller*/*Controlee* intercambian su `UwbAddress` y config por la sala,
  y abren una `RangingSession` → `RangingResult` con distancia + ángulo.

---

## 4. La realidad: no todos los teléfonos tienen UWB (clave para LatAm)

Esto es un límite real, no un detalle:

- **iOS:** iPhone **11 en adelante** (y Apple Watch 6+). Cobertura buena en el parque iPhone.
- **Android:** solo **gama alta** (Pixel 6 Pro+, Samsung S21+/Ultra y similares). **La gama media/baja,
  muy común en Chile/LatAm, NO trae UWB.**
- **iOS ↔ Android:** la interoperabilidad directa app-a-app está **emergiendo** (estándar FiRa),
  pero **no es plug-and-play**. Asumir, por ahora, iPhone↔iPhone y Android↔Android.

**Por eso la arquitectura debe ser en capas, con caída elegante:**

| Capa | Precisión | Dispositivos | Rol |
|---|---|---|---|
| **UWB** | ~10 cm + dirección | Solo gama alta (iPhone 11+, Android premium) | El "metro final" premium |
| **Bluetooth LE (RSSI)** | "caliente/frío", ~1-5 m | **Casi todos** | Fallback universal |
| **GPS + pin manual** | ~5-15 m | Todos | Base (lo que ya tienes) |

Regla: **usar UWB cuando ambos lo tienen; si no, Bluetooth "caliente/frío"; y siempre GPS de base.**
Nunca dejar al usuario sin nada.

---

## 5. Cómo lo aplicas (ruta práctica)

**A. La demo mínima para *sentirlo* (unas horas):**
- Consigue **dos iPhone 11 o más nuevos**.
- Compila el ejemplo oficial de Apple de **Nearby Interaction** (o "Implementing Interactions
  Between Users in Close Proximity").
- Camina con los dos: verás la **distancia y la flecha a ±10 cm**. *Esa es la demo que vende la
  Fase 2* (y la que valida el negocio B2B de recintos).

**B. Integrarlo en Proxi:**
1. Construir la **app nativa** (Swift para iOS, Kotlin para Android; o Flutter/React Native con
   *platform channels* nativos para UWB — los plugins de terceros aún son inmaduros).
2. Reusar la **sala de Firebase** como canal para intercambiar los tokens/direcciones UWB.
3. Implementar las **3 capas** (UWB → Bluetooth → GPS) con detección de capacidad en tiempo de
   ejecución y caída automática.
4. Mantener el **mapa** como está: UWB es para los últimos metros; el mapa sigue guiando de lejos.

**C. Alternativa/compañera:** la **cámara/VPS** de [`RECINTOS.md`](RECINTOS.md) resuelve el mismo
"metro final" sin depender de que ambos tengan UWB, a cambio de necesitar cámara y cobertura del
recinto. Las dos pueden convivir.

---

## 6. Resumen

- El "0 m exacto" que buscabas es **UWB** (o cámara/VPS), y **solo existe en app nativa**.
- Proxi ya tiene lo difícil del emparejamiento: **la sala de Firebase** hace de canal para UWB.
- Diseñar en **3 capas con fallback** por la fragmentación de dispositivos en LatAm.
- Primer paso barato y contundente: la **demo iPhone-a-iPhone** con el ejemplo de Apple.

---

_Relacionado: [`PLAN.md`](PLAN.md) · [`RECINTOS.md`](RECINTOS.md) (la otra vía al "metro final") ·
[`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md) (por qué el premium y el B2B pagan la Fase 2)._
