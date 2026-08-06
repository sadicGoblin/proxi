# Proxi Faro — "El último metro lo resuelve la retina, no el radio"

> Concepto para resolver el "último metro" **sin UWB, en cualquier teléfono**, y sobreviviendo a
> un concierto ruidoso. Resultado de una investigación multi-agente (7 vías exploradas + filtro
> adversarial). Documento separado de [`PLAN.md`](PLAN.md) · relacionado con [`UWB.md`](UWB.md)
> (que queda como *boost premium*, no como base).

_Generado el 2026-07-05 tras la prueba que mostró el límite del GPS y de UWB (solo gama alta)._

---

## 1) Idea central en una frase

**Proxi Faro** convierte el problema irresoluble de *medir* los últimos 10 m sin UWB en el problema
resoluble de *reconocer cuál de estas 20 personas es tu amigo*: el buscador recibe un **rumbo
estable** (no una posición métrica) y el buscado emite un **destello óptico de color+patrón único
por sesión** que el ojo humano —el mejor detector de parpadeo en la periferia que existe— engancha
entre la multitud y el ruido de 125 dB, porque el canal de cierre no es RF ni audio, es la **luz
sobre la retina**.

El resultado nuevo no es un sensor: es la **arquitectura de traspaso** (radio → rumbo visual →
retina) que garantiza que *siempre* hay una capa que funciona en cualquier teléfono, y que la capa
de cierre es inmune a lo único que un concierto siempre tiene (ruido acústico brutal y cuerpos que
bloquean RF).

---

## 2) Arquitectura en CAPAS con caída elegante

El sistema elige, **por par de teléfonos** y en runtime (por capacidades + condiciones), la capa
más precisa que ambos soporten, y degrada hacia abajo cuando falla. Las capas se **solapan**.

| Anillo | Distancia | Señal primaria | Qué entrega | Requisito |
|---|---|---|---|---|
| **0 · Macro** | > 30 m | GPS + mapa satelital + Firebase | Punto grueso + rumbo grueso | GPS (universal) |
| **1 · Aproximación** | 8–30 m | **BLE RSSI filtrado** (Kalman) → "caliente/frío" | Gradiente (te acercas/alejas) + **trigger** de capas caras | BLE 4.0+ (universal, incl. Vivo V25) |
| **2 · Rumbo** | 5–15 m | **Flecha estabilizada por VIO** (ARCore/ARKit), no brújula | Dirección estable pese a cuerpos y acero | ARCore/ARKit (Vivo V25 sí está en la lista) |
| **3 · CIERRE (estrella)** | 2–15 m con visión | **Baliza óptica**: flash LED + pantalla, color+patrón único, disparo remoto | El ojo clava a la persona exacta (~0,5 m) | Flash LED + pantalla (universal desde ~2011) |
| **3b · Auto-lock (opcional)** | 2–12 m | Visión on-device: detecta el color asignado parpadeando | Halo AR sobre el amigo | Cámara + CPU gama media+ |
| **4 · Métrico opt-in** | 0,5–6 m | **Ranging acústico** ultrasónico 18–20 kHz | Contador que baja real (5,1 → 0,7 m) | Parlante+mic calibrados (subconjunto) |

**Reglas de degradación (por par):**
- **Ambos ARCore + ambos calibran ultrasonido** → rumbo VIO + contador acústico + cierre óptico. Experiencia "AirTag".
- **Ambos ARCore, sin ultrasonido** → rumbo VIO + cierre óptico (flecha + destello, sin número).
- **Uno sin ARCore (gama muy baja)** → BLE "caliente/frío" + **cierre óptico (que es retina pura, no necesita ARCore)**.
- **iPhone ↔ Android** → BLE + ARKit/ARCore para rumbo + cierre óptico. Nada depende de UWB/RTT.
- **Sin línea de vista al final** → "levanta el teléfono/brazo"; si aún falla, vuelve a "caliente/frío".

**Invariante de diseño:** la **Capa 3 (óptica) nunca depende de las de arriba y funciona en el
teléfono más barato**. Todo lo demás solo *reduce el cono* que el ojo debe barrer.

---

## 3) El MECANISMO ESTRELLA: baliza óptica de sesión

**Por qué la retina y no el micrófono/radio.** Un concierto es 100–125 dB → el parlante es
inaudible a 15 m. Los cuerpos (~70% agua) atenúan 10–20 dB por persona en 2,4 GHz → el RSSI
absoluto es basura y no da dirección. **La luz modulada brillante se ve por encima y entre cabezas,
y el ojo humano detecta el parpadeo de un color saturado raro en la periferia mejor que cualquier
cámara.** El problema deja de ser "medir 3,2 m" y pasa a ser "¿cuál de estas 20 caras parpadea en
cian a 3 Hz hacia donde apunta mi flecha?" — que el cerebro resuelve en <1 s.

**Paso a paso:**
1. **Disparo remoto por la sala Firebase existente.** El buscador pulsa *"Pídele que se ilumine"* →
   evento en tiempo real por el canal que Proxi ya usa. Son bytes → sobrevive a la red saturada.
2. **Firma única por sesión.** El backend asigna **(color, patrón)** de una paleta de máxima rareza
   en conciertos: **cian, magenta, lima** (evita blanco/ámbar, que son las linternas del público y
   el light-show cálido). El patrón es un **strobe de baja frecuencia** (p.ej. 3 destellos + pausa,
   ~3–4 Hz): visible, trivial de generar, y crea una firma de movimiento que el cerebro engancha.
   (color × patrón) evita colisiones con búsquedas simultáneas.
3. **Emisión en 2 canales por penetración:**
   - **Flash LED trasero** (principal): togglear con un `Timer` sobre `setTorchMode` (Android) /
     `AVCaptureDevice.torchMode` (iOS). 30–200 lm, la fuente más penetrante, basta a 15 m.
   - **Pantalla completa** a color saturado con brillo 1.0 (sin permiso de sistema): gran área,
     ideal de noche, y es lo que la persona muestra levantando el teléfono.
4. **Guía direccional en el buscador.** Overlay AR (rumbo de Capa 2) que dice literalmente:
   **"Busca el DESTELLO CIAN — 3 parpadeos — hacia allá →"**. El cono estrecha el área de 360° a
   ~30–45°. El buscador ve el destello, camina, pulsa **"¡Lo veo!"** → cierra sesión y apaga la baliza.
5. **Auto-lock opcional (gama media+).** La cámara busca una mancha del color asignado parpadeando a
   la frecuencia conocida (correlación temporal simple) y dibuja un halo AR. Degrada a puro-humano
   en gama baja: la retina no necesita la cámara.

**Por qué es ingenioso y no un simple strobe:** existen apps de linterna (Flare, CrowdGlow) pero son
manuales y tontas. La estrella es el **lazo orquestado**: (a) disparo remoto bajo demanda por el par
ya emparejado, (b) firma color+patrón asignada dinámicamente y **reasignada** si el escenario proyecta
ese color, (c) fusión con un **rumbo que le dice al ojo dónde mirar**, (d) activación efímera (15–30 s,
autoapagado) que resuelve batería, saturación y privacidad de golpe. Es "Precision Finding de AirTag"
con retina humana, en un teléfono de 150 USD, sin UWB.

**Defensas multiplicativas contra el ruido visual:** color raro (magenta/lima) fuera de las linternas
blancas/ámbar · patrón temporal que sobrevive aunque el color se confunda (y cubre el ~8% de daltonismo)
· cono AR que reduce el área · reasignación dinámica si el light-show baña la sala del color asignado.

---

## 4) Por qué es defendible/novedoso

- **Vs. solo-GPS:** el GPS (±10–15 m, muere en interior de estadio) no distingue a tu amigo de 30
  desconocidos en ese radio. Faro no compite en esa escala: lo usa como anillo macro y resuelve por
  debajo, identificando a la persona exacta (~0,5 m efectivos) que ningún GPS alcanza.
- **Vs. UWB:** UWB da 10–30 cm pero es coto de flagships (viola la universalidad, requisito
  innegociable para gama media LatAm). Faro logra el mismo *objetivo de producto* con hardware
  presente en todo teléfono desde 2011, y es **inmune al bloqueo por cuerpos (NLoS) que también
  degrada al UWB**.
- **La novedad honesta:** la física no es nueva (VLC, PDR, acústica, BLE tienen 15–25 años). Lo nuevo
  como *sistema* es: (1) la arquitectura de traspaso por anillos con **invariante de universalidad**;
  (2) el **cierre óptico orquestado** (disparo remoto + firma única + reasignación antiruido + guía de
  rumbo + confirmación humana); (3) usar la **banda de menor ruido según el entorno** (retina en el
  concierto; ultrasonido como canal silencioso para el número opt-in). Es endurecimiento para entorno
  hostil + experiencia de traspaso, sin sobre-reclamar.

---

## 5) Qué PROTOTIPAR PRIMERO (con S25 + Vivo V25 + emulador)

**Hipótesis que mata el concepto si falla:** *un buscador guiado por una firma color+patrón localiza
al buscado a 10–15 m con distractores, más rápido y con menos error que con solo "caliente/frío" BLE.*

**MVP = Capa 1 + Capa 3 (BLE trigger + baliza óptica). Sin ARCore, sin ultrasonido, sin visión.
Construible en días.**

**Stack:** `flutter_blue_plus` + `flutter_ble_peripheral` (handshake/trigger) · Firebase (ya existe:
sala + evento "ilumínate" + asignación color/patrón) · `torch_light` (strobe LED) · `screen_brightness`
+ `Container` full-screen (canal pantalla) · `vibration` (cierre en mano).

**Roles de los equipos:**
- **Vivo V25** (gama media, el caso crítico) = **el buscado**: emite el destello. Si funciona aquí,
  funciona en el parque LatAm.
- **Samsung S25** = **el buscador**: rumbo grueso + "busca CIAN, 3 parpadeos, hacia allá" + botón "¡Lo veo!".
- **Emulador** = tercer nodo Firebase para probar **sesiones concurrentes** y la asignación única
  (color, patrón). (Sin BLE/flash reales: solo valida la orquestación, no la física óptica.)

**Protocolo medible:** con ~10–15 personas de pie (varias con linternas blancas de fondo), buscado a
10 m. Cronometrar **tiempo-a-reconocimiento** y **acierto** con: (A) solo BLE caliente/frío vs (B) BLE
+ baliza óptica. Repetir con el buscado tapado (levantando vs no el teléfono) y con 2–3 balizas de
distinto color a la vez (no-colisión).

**Criterio de éxito:** (B) reduce el tiempo a la mitad y sube el acierto a >90% con visión parcial.
Si se sostiene, se justifica Capa 2 (VIO) y Capa 4 (acústica). Si no, el concepto "retina como cierre"
queda falseado antes de escribir una línea de DSP.

---

## 6) Límites honestos

- **Línea de vista es la condición dura.** Si el buscado queda 100% tapado, el destello no se ve. Se
  mitiga con "levanta el teléfono/brazo" y el cono AR, pero **depende de cooperación bilateral**. A 15 m
  casi siempre hay ángulo por encima de las cabezas; en un mosh pit a ras de suelo, no.
- **No entrega metros** (salvo Capa 4 opt-in, fiable solo 3–6 m). Da dirección + caliente/frío +
  reconocimiento. La UX debe prometer **"te llevo hasta verlo"**, no "flecha a 2,0 m exactos".
- **Ruido visual a escala:** medio estadio con balizas o un light-show del color asignado puede ahogar
  un destello. Se mitiga con paleta rara + reasignación + patrón + efímero, pero hay techo de sesiones
  concurrentes por color.
- **El auto-lock por cámara (3b) es frágil** a 15 m; es bonus, nunca ruta crítica. La ruta crítica es el ojo.
- **La Capa 2 (VIO)** puede perder tracking en oscuridad total y consume batería → se enciende solo en
  aproximación final (<30 m, disparada por BLE).
- **La Capa 4 acústica** hereda sus riesgos (roll-off sobre 20 kHz, calibración por modelo, audible por
  jóvenes/mascotas) → **opt-in, nunca base**.
- **Privacidad/seguridad social:** iluminarse revela tu posición a cualquiera cerca. Mitigación
  obligatoria: baliza **voluntaria, efímera (15–30 s), con consentimiento por sesión y token rotatorio**
  → encaja con privacy-by-design de la Ley 21.719 (ver [`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md) §6).
- **Batería:** strobe + pantalla + escaneo BLE drenan → baliza corta autoapagada + duty-cycling.
- **iOS en segundo plano** estrangula BLE → el flujo asume **primer plano ("modo búsqueda activa")**.

---

## Anexo — Las 7 vías exploradas (y por qué ganó la óptica)

| Vía | Veredicto | Universal (gama media) | Sobrevive al ruido |
|---|---|---|---|
| **Baliza óptica "Marco Polo"** ⭐ | **Mantener (92)** | ✅ | ✅ (canal = retina) |
| Rumbo por cámara/AR (VIO) | Combinar → Capa 2 | ✅ ARCore/ARKit | ✅ (visual) |
| BLE RSSI "caliente/frío" | Combinar → Capa 1 | ✅ | parcial (trigger, no dirección) |
| Ranging acústico (ultrasonido) | Combinar → Capa 4 opt-in | subconjunto | ❌ en 125 dB → solo opt-in |
| Fusión IMU / dead-reckoning | Apoyo | ✅ | ✅ pero deriva |
| WiFi RTT / Aware | Descartar como base | fragmentado | — |
| Malla de multitud | Descartar (complejo) | requiere densidad | — |

_Investigación completa archivada en el journal del workflow._
