# Proxi para Recintos — VPS privado (idea a desarrollar aparte)

> Línea de producto B2B: el organizador "mapea" su lugar una vez (subiendo video/fotos) y Proxi
> construye un **mapa visual privado** del recinto. Durante el evento, la cámara del teléfono
> reconoce el espacio y ubica a cada persona con precisión de **centímetros a 1 metro**,
> incluso en interiores o bajo techo donde el GPS y el VPS de Google no llegan.

_Idea planteada por el usuario el 2026-07-05. Documento separado de [`PLAN.md`](PLAN.md)._

---

## 1. La idea en una frase

Subes un recorrido en video (o fotos) del lugar → Proxi lo procesa en la nube y crea una
"huella visual" del recinto → los asistentes apuntan la cámara unos segundos y la app sabe
**exactamente** dónde están, sobre el mapa que ya muestra la app.

---

## 2. Por qué es valiosa

- **Cubre lo que Google no cubre.** El VPS de Google (ARCore Geospatial) funciona donde hay
  Street View: calles, ciudades. **No** funciona bien en interiores, estadios techados,
  galpones, recintos privados, festivales en campos. Ahí es donde más se pierde la gente y
  donde el GPS es peor. Ese es tu territorio.
- **Es un moat (barrera).** Cada recinto mapeado es un activo tuyo. Mientras más lugares
  mapeas, más difícil es competir contigo.
- **Es mejor negocio que solo consumidores.** Le vendes al organizador (que sí paga), no solo
  a usuarios que quieren gratis. Ver el modelo de venta abajo.

---

## 3. Qué es, técnicamente

Se llama **relocalización visual** o **VPS (Visual Positioning System) privado**. La cámara
compara lo que ve en vivo contra un modelo 3D del lugar y calcula su posición y orientación.
Dos piezas:

1. **El mapa del recinto** (se crea una sola vez): una nube de puntos 3D + "descriptores"
   visuales de las esquinas, texturas y estructuras estables del lugar.
2. **La localización** (cada vez que alguien usa la app): el teléfono extrae rasgos de la
   imagen en vivo y los calza contra ese mapa → obtiene su pose (posición + hacia dónde mira).

Opcionalmente, el mismo material sirve para generar el **mapa 3D fotorrealista** (con NeRF o
Gaussian Splatting) que da la vista bonita que imaginabas al principio.

---

## 4. Cómo debería hacerse el trabajo (el pipeline)

### Paso 1 — Captura (la hace el organizador, una vez)
- Recorrer el recinto grabando **video lento con buena cobertura**: todos los sectores,
  distintos ángulos, sin correr, con solapamiento entre tomas.
- Mejor con una **app guiada** (estilo Polycam / Matterport) que le indique al organizador qué
  zonas faltan por cubrir.
- Regla de oro: capturar en **condiciones parecidas al evento** (si el concierto es de noche,
  mapear de noche) y apuntando a **estructuras estables** (muros, escenario, rejas), no a
  cosas que cambian (personas, autos).

### Paso 2 — Procesamiento en la nube
- **Structure-from-Motion (SfM) / fotogrametría**: reconstruye la geometría 3D y las
  posiciones de cámara a partir de los frames. (Herramientas: COLMAP, RealityCapture, Metashape.)
- Se extraen y guardan **rasgos visuales** (keypoints + descriptores) → ese es el "mapa de
  localización" contra el que se calzará el teléfono.
- (Opcional) generar un **NeRF / 3D Gaussian Splatting** para la vista 3D fotorrealista.
- Se ancla el mapa a coordenadas reales (georreferenciado) para que calce con el mapa 2D.

### Paso 3 — Localización (la hacen los asistentes en vivo)
- La app abre la cámara, extrae rasgos del frame y los **calza contra el mapa del recinto**.
- Devuelve la pose precisa (~10–50 cm en buenas condiciones).
- Entre relocalizaciones, el teléfono sigue la posición con **VIO** (odometría visual-inercial,
  la cámara + giroscopio) para no tener que estar mirando siempre; se recalibra cada tanto.

### Paso 4 — Integración con la app actual
- La posición precisa se coloca **sobre el mismo mapa/plano** que ya muestra Proxi y se comparte
  en vivo, igual que hoy — pero ahora viene de la cámara, no del GPS.
- **Degradación elegante:** si la cámara no reconoce (poca luz, multitud tapando todo), la app
  cae automáticamente a GPS + pin manual. Nunca se queda sin ubicación, solo con menos precisión.

---

## 5. Con qué tecnología: comprar vs. construir

Empezar **comprando un SDK** (rápido, valida la idea); construir lo propio solo si el volumen
lo justifica. _(Verificar disponibilidad y precios actuales antes de decidir — cambian seguido.)_

| Opción | Qué hace | Bueno para | Nota |
|---|---|---|---|
| **Immersal** (Hexagon) | Subes imágenes → nube arma el mapa → SDK localiza | Espacios grandes, interiores. **El match más directo** a esta idea | Empezar aquí para el piloto |
| **Niantic / Lightship VPS** | Escaneo de lugares + posicionamiento visual | AR a gran escala | Verificar estado del producto |
| **Google ARCore Cloud Anchors** | Ancla puntos que persisten (hasta ~1 año) | Áreas acotadas | Complementa al VPS de Google |
| **Apple ARKit — ARWorldMap** | Guardar y recargar el "mapa del mundo" de una zona | Recintos acotados en iOS | Nativo iOS |
| **Construir propio** | COLMAP + emparejadores aprendidos (SuperPoint/LightGlue, pipeline hloc) | Control total, sin costo por escaneo | Pesado; solo cuando haya escala |
| **NeRF / Gaussian Splatting** (Polycam, Luma, gsplat) | Vista 3D fotorrealista del lugar | La capa visual "bonita" | La localización igual necesita el mapa de rasgos |

> Azure Spatial Anchors (Microsoft) **fue descontinuado** — no construir sobre él.

---

## 6. El modelo de venta: "Proxi Recintos" (B2B)

Este es el negocio que preguntabas. Le vendes al **dueño del recinto o al productor del evento**:

- **Fee de mapeo (una vez por lugar):** capturar y procesar el recinto. Puede ser servicio
  hecho por ti, o self-service con la app guiada (más barato y escalable).
- **Suscripción / licencia:** hosting del mapa del recinto + soporte. Por **mes** (recinto
  permanente: estadio, mall, centro de convenciones) o por **evento** (festival puntual).
- **Por asistente / por evento activo:** opcional, si el volumen es alto.
- **Marca blanca / patrocinio:** el recinto o un sponsor pone su logo dentro de la experiencia.

Idea de estructura (a validar con la investigación de mercado): *setup* de mapeo + *SaaS*
recurrente. Los recintos permanentes dan ingreso estable; los festivales dan picos.

---

## 7. Cómo organizar el trabajo, por fases

- [ ] **Fase A — Validar precisión (1 recinto piloto).** Tomar UN lugar real, mapearlo con un
  SDK (Immersal), medir qué precisión logras de día/noche, con y sin gente. ¿Sirve o no?
- [ ] **Fase B — Flujo de captura guiada + portal.** App que guía al organizador a grabar bien,
  y un panel donde sube/gestiona el mapa de su recinto.
- [ ] **Fase C — Localización en vivo + integración** con el mapa 2D de Proxi y la caída elegante
  a GPS/manual.
- [ ] **Fase D — Empaquetar como producto vendible** ("Proxi Recintos") con precios y contrato.

---

## 8. Límites y riesgos honestos

- **Luz y multitud:** cambios de iluminación y gente tapando el fondo degradan el reconocimiento.
  Mitigar: mapear en condiciones similares y anclar a estructuras estables.
- **Necesita apuntar a algo reconocible:** no funciona apuntando al cielo o a una masa uniforme
  de gente. Por eso la caída a GPS/manual es obligatoria.
- **Batería y cómputo:** localizar con cámara consume; se hace por ráfagas + VIO en medio.
- **Privacidad:** el video del recinto es del organizador (dato sensible, guardarlo seguro).
  Los frames de la cámara del asistente deben procesarse en el dispositivo o de forma efímera,
  nunca almacenarse. Esto además es exigencia legal (ver privacidad en `PLAN.md`).
- **Costo de mapeo:** mapear bien un recinto grande toma trabajo; por eso se cobra.

---

## 9. Próximo paso mínimo para validar

Elegir **un solo espacio** (tu oficina, un galpón, una plaza chica), grabarlo con el móvil,
procesarlo con un SDK gratuito de prueba (Immersal) y medir la precisión real que se logra.
Con ese número decides si vale la pena construir la línea completa.

---

_Relacionado: [`PLAN.md`](PLAN.md) (producto principal) · Fase avanzada de precisión (cámara/VPS)._
