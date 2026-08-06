# Proxi — Plan de producto

> Encuentra a la persona exacta, no el área aproximada.
> Ubicación precisa (a metros) en espacios llenos de gente: conciertos, festivales, estadios, plazas.

---

## 📁 Documentos del proyecto

- **[`PLAN.md`](PLAN.md)** — este documento: producto, tecnología y roadmap.
- **[`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md)** — cómo se vende y monetiza (investigación de mercado).
- **[`RECINTOS.md`](RECINTOS.md)** — línea B2B: mapear el recinto con video para reconocimiento visual (VPS privado).
- **[`UWB.md`](UWB.md)** — el "metro final" premium: UWB en app nativa para verse a ~10 cm (solo gama alta).
- **[`FARO.md`](FARO.md)** ⭐ — el "metro final" **universal, sin UWB**: baliza óptica (la retina cierra el último metro). El concepto más fuerte.
- **[`prototipo.html`](prototipo.html)** — maqueta visual interactiva (concepto).
- **[`public/`](public/)** — web app real desplegada en Firebase para probar entre 2 personas.
- **[`public/junta.html`](public/junta.html)** 🚩 — **Junta del grupo**: punto de encuentro + hora compartidos por sala; cualquiera lo mueve o cambia la hora y todo el grupo lo ve al instante (con historial de cambios). Sin instalar nada, solo un link.
- **[`proxi_app/`](proxi_app/)** — app Flutter (Android): mapa + en vivo + **UWB** (±10 cm). Fase 2.

---

## 1. El problema

Cuando estás en un lugar con MUCHA gente (un concierto, un festival, un estadio), compartir "mi ubicación" por WhatsApp/Google Maps **no sirve**:

- El GPS del teléfono tiene un error típico de **5 a 20 metros**, y **empeora** cuando hay:
  - Multitudes (cuerpos bloquean la señal).
  - Edificios altos alrededor ("cañones urbanos" que rebotan la señal).
  - Techos, carpas o estructuras (estadios cubiertos).
- En una multitud, 15 metros de error = **imposible encontrarse**. Estás "al lado" según el mapa pero no se ven.

**La necesidad real:** pasar de precisión de ~15 m a precisión de **1–3 m**, y que sea fácil de compartir con alguien que quizás ni tiene la app instalada.

---

## 2. La idea (en tus palabras, ordenada)

1. Abro Proxi y **marco mi punto exacto** sobre un mapa muy detallado (idealmente 3D, como el de Google), con un doble-tap.
2. Genero un **link / invitación** y se lo mando a alguien (por WhatsApp, o si es "amigo/cercano" dentro de la app).
3. Esa persona abre el link, ve **exactamente** dónde estoy sobre ese mismo mapa detallado, y camina hacia mí.
4. Bonus: ver en tiempo real cómo nos acercamos ("estás a 12 m, gira a la derecha").

---

## 3. La pieza de tecnología que te falta (importante)

Tu intuición de "escanear el mapa 3D de Google alrededor" **ya existe como tecnología** y se llama **VPS (Visual Positioning System)**. Es EXACTAMENTE lo que describes:

- **Google Geospatial API (ARCore)**: usas la cámara del teléfono, la app compara lo que ve con las imágenes de Street View / modelo 3D de Google, y calcula tu posición con precisión de **~1 metro** (mucho mejor que el GPS). Funciona apuntando la cámara alrededor unos segundos.
- **Photorealistic 3D Tiles (Google Maps Platform)**: es el mapa 3D fotorrealista de Google que puedes incrustar en tu app para que la gente vea el entorno como lo describes.

Esto significa que hay **dos maneras** de lograr la precisión, y probablemente conviene combinarlas:

| Enfoque | Cómo funciona | Precisión | Dificultad |
|---|---|---|---|
| **A. Corrección manual** (tu doble-tap) | El usuario ajusta a mano su pin sobre un mapa muy detallado | Depende del usuario, pero un humano corrige mejor que el GPS | **Baja** ✅ |
| **B. VPS con cámara** (ARCore Geospatial) | La cámara "reconoce" el lugar y te ubica sola | ~1 m | Media-alta |
| **C. Proximidad directa** (Bluetooth/UWB) | Los dos teléfonos se detectan entre sí en los últimos metros | <1 m en cercanía | Media |

**Recomendación:** empezar por **A** (rápido, barato, valida la idea), y sumar **B** después como el gran diferenciador.

---

## 4. Enfoque recomendado: MVP primero

No construyas todo de una. La versión mínima que ya resuelve el 80% del dolor:

### MVP (v0.1) — "Pin preciso + link"
- Mapa detallado (Google Maps o Mapbox) centrado en tu ubicación GPS aproximada.
- **Capas de base intercambiables:** oscuro/calles, **satélite** y **relieve** (las que ya da el SDK de Google Maps).
- **Doble-tap para colocar tu pin exacto** (corrección manual).
- **Zoom adaptativo:** a medida que las dos personas se acercan, el mapa hace zoom solo y **carga más detalle** (rejilla de metros, barra de escala). Los últimos metros son los que importan.
- Botón **"Compartir"** → genera un link.
- Quien abre el link ve tu pin exacto sobre el mismo mapa (aunque no tenga la app → se abre en el navegador).
- Distancia y flecha "hacia la persona" en vivo.

Esto **no necesita cámara, ni AR, ni 3D todavía**. Es construible y ya es útil.

### v0.2 — Social
- Cuentas / login.
- Agregar "cercanos" o amigos.
- Compartir ubicación en vivo (no solo un pin fijo).

### v0.3 — El diferenciador
- Mapa **3D fotorrealista** de Google.
- **VPS con cámara** (ARCore Geospatial) para ubicación a ~1 m sin corrección manual.
- Modo AR: apuntas la cámara y ves una flecha flotante hacia tu amigo.

---

## 5. Arquitectura técnica (borrador)

**Plataforma:** móvil (la cámara y el GPS son clave) → **iOS + Android**.

- **Opción rápida multiplataforma:** React Native o **Flutter** (un solo código para iOS y Android).
- **Para AR/VPS serio:** quizás nativo (ARKit en iOS, ARCore en Android) o **Unity** con AR Foundation.

**Componentes:**
- App móvil (Flutter/React Native).
- **Backend** ligero: usuarios, amigos, y compartir ubicaciones en vivo → **Firebase** (rápido: auth + base de datos en tiempo real + hosting de links) es ideal para un MVP.
- **Mapas:** Google Maps SDK (y Photorealistic 3D Tiles / Geospatial API más adelante).
- **Links compartibles:** una web simple (el link abre un mini-mapa en el navegador).

---

## 6. Roadmap por fases

- [ ] **Fase 0 — Definición** (este documento) + decisiones abiertas de abajo.
- [ ] **Fase 1 — Prototipo de pantalla:** un mapa donde puedo poner un pin con doble-tap. (Sin backend, solo para "verlo").
- [ ] **Fase 2 — Compartir por link:** generar un link que muestre ese pin a otra persona.
- [ ] **Fase 3 — En vivo + amigos:** cuentas, agregar cercanos, ubicación en tiempo real.
- [ ] **Fase 4 — Precisión pro:** VPS con cámara + mapa 3D + modo AR.

---

## 6.1 Decisiones tomadas (2026-07-04)

- **Plataforma:** móvil **iOS + Android** (un solo código con Flutter o React Native).
- **Cómo construir:** **prototipo visual primero** — maqueta clicable antes de código real. → ver [`prototipo.html`](prototipo.html).
- **Precisión del MVP:** **doble-tap manual** (Fase 1). La cámara/VPS queda para fases posteriores.

---

## 7. Decisiones abiertas (a definir juntos)

1. **Plataforma:** ¿iOS, Android, o ambos? ¿Y una versión web para el que recibe el link sin la app?
2. **¿Quién construye?** ¿Tú aprendiendo, contratar a alguien, o co-construir conmigo paso a paso?
3. **Precisión mínima aceptable** para el MVP: ¿basta la corrección manual (doble-tap), o el objetivo desde el día 1 es la cámara/VPS?
4. **Modelo de negocio:** ✅ investigado → ver [`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md). Resumen: consumo gratis/viral + ingreso real B2B2C (organizadores) y patrocinio; NO suscripción social de pago (lección Zenly).
5. **Privacidad:** ✅ investigado → ver [`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md) §6. La **Ley 21.719** (vigente 1-dic-2026) obliga a diseño *privacy-by-design*: consentimiento mutuo y por sesión, pin que expira, revocable, sin venta de datos. Pendiente: implementarlo en el producto.

---

## 8. Riesgos y notas honestas

- El **VPS con cámara** necesita que Google tenga cobertura del lugar (buena en ciudades, pobre dentro de recintos cerrados). No es magia en todos lados.
- **Bluetooth/UWB** entre dos teléfonos funciona muy bien en los últimos metros, pero requiere que ambos tengan la app abierta.
- La **batería** y los **permisos** (cámara + ubicación) son fricción real para el usuario.
- Empezar por lo simple (doble-tap + link) permite validar si la gente realmente lo usaría **antes** de invertir en lo complejo.

---

_Última actualización: 2026-07-04_
