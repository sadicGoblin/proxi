# Proxi — Modelo de negocio

> Síntesis de la investigación de mercado (6 ángulos, Chile/LatAm, 2026). Documento vivo,
> complementa [`PLAN.md`](PLAN.md) y [`RECINTOS.md`](RECINTOS.md).

**La conclusión en una frase:** cobrarle al asistente por "encontrar amigos" es el camino que
mató a Zenly; el dinero real está en **venderle al organizador del evento (B2B2C) y a las marcas
patrocinadoras**, con una capa de consumo **gratis y viral** que alimenta esa venta.

---

## 1. El aprendizaje que define todo: por qué NO una app social de pago

- **Zenly** llegó a **40 millones de usuarios activos** y aun así Snap la **cerró en feb-2023**:
  nunca monetizó y su base estaba en mercados de bajo ARPU (Japón, Vietnam, Indonesia) — el
  mismo perfil que LatAm. Excelencia de producto ≠ negocio.
- **Compartir ubicación ya es gratis** y de gigantes: Apple Find My (+2.000M dispositivos),
  Snap Map (400M usuarios), WhatsApp y Google Maps live location. El consumidor **espera que sea
  gratis**.
- El **único** caso probado de cobrar directo es **Life360**: US$489,5M de ingresos en 2025,
  primer año con utilidad (US$150,8M)… y funciona porque se vende como **seguridad familiar**, no
  como red social. Su conversión es solo **~3%** (2,8M pagan de 95,8M usuarios).
- El uso de Proxi es **en ráfagas** (solo durante el evento). Eso **destruye la retención** de
  suscripción: el 84% de las cancelaciones de prueba ocurren en el día 0-1. Freemium de consumo
  convierte apenas **2-5%** y el ingreso por instalación es ~US$0,38.

**Implicancia:** el consumidor es el **motor de adquisición y de datos**, no la fuente de ingreso.

---

## 2. Segmentos y la cuña de entrada

| Segmento | Quién paga | Por qué | Rol |
|---|---|---|---|
| **B2C (asistente)** | Nadie (gratis) / pago único ocasional | Espera gratis; uso en ráfagas | **Viralidad + datos**, no ingreso |
| **B2B2C (organizador/venue)** ⭐ | Productora, estadio, municipio | Paga por seguridad, experiencia y gestión de multitudes | **Ingreso principal** |
| **Patrocinio (marcas)** ⭐ | Telco, cerveza, banco | Ya es ~35% del ingreso de un festival; quiere métricas geolocalizadas | **Ingreso principal** |

**Cuña recomendada (doble y secuencial):**
1. **Capa de consumo viral** con lo que ya tienes: corrección de pin + compartir por **link web**
   (cero fricción de app store). Sembrarla en **2-3 festivales insignia** para generar tracción y
   datos de uso reales.
2. **En paralelo, UN piloto B2B pagado** con una **productora ancla**. En Chile la más obvia es
   **Lotus** (produce Lollapalooza *y* Fauna Primavera) o un **venue** (Movistar Arena, Estadio
   Nacional). Pocos gatekeepers = venta enfocada. Cerrar uno abre varios eventos.

> El **AR/VPS es Fase 2**, no la apuesta inicial: su cobertura (Street View de Google) en parques
> y estadios chilenos es incierta. Validar el negocio con pin+link antes de invertir en AR.

---

## 3. El mercado (por qué Chile primero, y luego LatAm)

- **Chile**: productoras (AGEPEC) facturaron **~US$191M en 2024** (187 eventos, +9M tickets), el
  **81% en la Región Metropolitana** → mercado chico pero **denso y profesionalizado**, ideal como
  banco de pruebas.
- **Mega-eventos que son tu cliente ideal**: **Lollapalooza** (~80.000/día, récord 225.000),
  **Fauna Primavera** (~30.000), **Estadio Nacional** (56-60k), **Movistar Arena** (12-16k).
- **El dolor está validado**: en multitudes las torres celulares se saturan y el pin de GPS se
  desvía **9-15 m** — justo el margen entre reencontrarse o perderse.
- **Expansión**: el mercado de música en vivo de LatAm vale ~US$2,2 mil millones (2025) y los
  **festivales crecen ~23% anual** (el más rápido del mundo). Polos: Bogotá, CDMX, Buenos Aires,
  São Paulo.
- **Infraestructura lista** (96,5% hogares con internet, 5G masivo) pero **la red colapsa dentro
  del evento** → Proxi debe funcionar **offline-first / degradado**.

---

## 4. Cómo se cobra (modelos validados en el sector, con precios de referencia)

> ⚠️ Son rangos de EE.UU./Europa. Para Chile/LatAm hay que **ajustar a la baja** o ir a
> **revenue-share con patrocinio**. Úsalos como techo, no como precio local.

| Modelo | Referencia de precio | Encaja para |
|---|---|---|
| **Licencia por evento** | US$1.000-5.000 básico · US$5.000-25.000 white-label · US$40.000+ a medida | Festivales puntuales (Lolla, Fauna, Sónar) |
| **Patrocinio ("Proxi presented by…")** ⭐ | A negociar (sin tarifa pública) | El de **menor fricción** en LatAm: gratis para el público, lo paga la marca. Precedente: app de Lollapalooza *"presented by Bud Light"* |
| **SaaS anual por recinto** | ~US$165-200 por mapa/edificio al mes (ref. Mappedin) | Estadios/arenas con calendario recurrente |
| **Por asistente activo** | ~£1,20/asistente (ref. cashless Weezevent); RFID US$0,10-5 | Eventos grandes; combinar con mínimo garantizado |
| **Event Pass (consumo)** | Pago **único no renovable** (no suscripción) | Desbloquear precisión/AR "para este evento". Sube conversión total 15-25% |
| **Analítica post-evento** | Add-on del contrato B2B | Heatmaps de flujo anonimizados para organizador y marcas |

**El argumento de venta al organizador es ROI + seguridad**, no "una app linda":
- **Seguridad/reunificación** (personas y niños extraviados) — presupuesto institucional, mayor
  disposición a pagar, y alineado con el foco de "seguridad y confiabilidad" de productoras como Lotus.
- **Gestión de multitudes**: la ubicación agregada (mapas de densidad) entra por el presupuesto de
  *safety/operaciones*. El 77% de los organizadores ya usan datos de multitud en tiempo real.
- **Más gasto per cápita**: el precedente del RFID muestra +15-30% de gasto (Coachella +25%).

---

## 5. ¿App móvil o web? (tu pregunta)

Ambas, pero en **orden**:

1. **Web primero** para quien **recibe el link** (no instala nada) → es lo que hace a Proxi viral y
   esquiva la fricción de la app store. Es tu motor de adquisición.
2. **App móvil nativa (iOS+Android)** cuando entres a lo premium: **cámara/VPS/AR**, ubicación en
   segundo plano, notificaciones, mejor batería. La app nativa es requisito técnico de la Fase 2,
   no del MVP.
3. **SDK/módulo white-label**: en vez de competir con las apps oficiales de festival, **véndeles tu
   "buscador de precisión" como componente** que ellos integran (revenue-share). Acelera distribución.

---

## 6. Privacidad = riesgo Y foso competitivo (no opcional)

Esto **condiciona el modelo de negocio**, no es letra chica:

- **Ley 21.719 (Chile)** entra en vigencia el **1-dic-2026**: la **ubicación precisa es dato
  sensible**, exige **consentimiento explícito**, y las multas llegan a **20.000 UTM (~US$1,5M)** o
  **4% de los ingresos**. Nace una Agencia (APDP) con poder real de fiscalizar.
- La ubicación puede ser **dato de categoría especial** cuando revela religión/política/orientación
  (marchas, actos religiosos, eventos LGBT+, conciertos) → justo los casos de Proxi.
- **Doble uso real**: la misma precisión que reúne amigos facilita el **acoso y control coercitivo**
  (precedente Life360). En un país con violencia de género grave, un diseño con rastreo encubierto o
  no-mutuo es riesgo reputacional, legal y humano.
- **Prohibido monetizar vendiendo datos de ubicación**: a Life360 le costó escándalo, demandas y una
  **orden de la FTC (ene-2025)**. Ese camino está **cerrado**.

**Diseño obligatorio (privacy-by-design):** opt-in **por sesión** y **mutuo** (ambos consienten),
**expiración automática**, sin rastreo en segundo plano oculto, revocación tan fácil como activar,
consentimiento parental para menores, y en la Fase AR **procesar en el dispositivo sin guardar
imágenes de terceros**. **Vender esto como diferenciador**: "consent-native, efímero y mutuo".

---

## 7. Recomendación de modelo (resumen accionable)

1. **Ingreso principal:** B2B2C (licencia/white-label a productoras y venues) + **patrocinio**.
2. **Consumo:** gratis (pin + link web) como motor viral; **Event Pass de pago único** opcional; NO
   suscripción obligatoria. Suscripción ligera solo para power users (padres, guías, frecuentes).
3. **Narrativa:** **seguridad y reencuentro**, no "red social" (así paga Life360, así murió Zenly).
4. **Cuña:** sembrar en 2-3 festivales + cerrar 1 productora/venue ancla en Chile.
5. **Descartar explícitamente:** venta/corretaje de datos y publicidad basada en ubicación.
6. **Construir la monetización desde el día 1** (la lección Zenly), con privacy-by-design como foso.

---

## 8. Riesgos principales (y mitigación)

| Riesgo | Mitigación |
|---|---|
| Gigantes gratis (Find My, Snap Map) copian el feature | Ganar el **nicho de precisión en multitud** + valor B2B que ellos no dan |
| Trampa Zenly (crecer sin monetizar) | Ingreso B2B **desde el día 1** |
| Ley 21.719 / privacidad | Privacy-by-design; consentimiento mutuo y efímero; cero venta de datos |
| Red saturada en el evento | **Offline-first**; el pin+link es robusto; explorar edge/mesh |
| Estacionalidad + pocos clientes concentrados | Contratos B2B recurrentes por venue; expandir pronto a MX/BR/AR/CO |
| Cobertura VPS incierta (Fase 2) | Validar por recinto; caída elegante a GPS/manual; ver [`RECINTOS.md`](RECINTOS.md) |

---

## 9. Cómo leer estas cifras (honestidad)

Los montos de mercado y precios vienen de reportes de la industria y de comparables (Life360,
Mappedin, Weezevent, AGEPEC, RevenueCat). Son **referencia**, no promesas: los precios de EE.UU./EU
casi siempre hay que **ajustarlos a la baja para Chile/LatAm**. Las fuentes quedaron registradas en
la investigación; conviene **re-verificar cifras clave** (y la fecha de vigencia de la Ley 21.719)
antes de usarlas en una presentación o levantamiento de capital.

---

_Fuentes principales: AGEPEC 2025, Life360 FY2025 (SEC), RevenueCat 2026, Pragmatic Engineer
(Zenly), The Markup/FTC (Life360 data), Mappedin, Weezevent, ProudTek, XMS Latam (Ley 21.719),
Google ARCore/Maps docs. Investigación completa archivada en el journal del workflow._
