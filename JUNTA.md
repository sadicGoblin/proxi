# Proxi — Spec: compartir bien, marcar bien, y la Junta con roles

> Estado: **Ronda 1 implementada (2026-08-06)** — Anonymous Auth + reglas reales + F3.1–F3.4 +
> F2.1 + "pedir mover" (F3.5 lite). Decisiones P1–P5 registradas en §5.
> Contexto: Faro (baliza óptica) probado y descartado. Mientras se investiga la
> mejor vía para ubicación precisa, el foco es hacer impecable lo básico: **compartir ubicación,
> marcar el punto, y una junta que no se mueva sola**.

Cada función tiene un ID para poder discutirlas una a una ("la F3.2 sí, la F3.5 después").

---

## 1. Compartir ubicación bien

| ID | Función | Detalle | Estado |
|---|---|---|---|
| F1.1 | **Pausar / reanudar** mi ubicación | Botón visible "dejar de compartir" sin salir de la sala. Hoy compartes siempre mientras la pestaña viva. | propuesta |
| F1.2 | **Presencia honesta** | Junto a cada persona: "visto hace 12 s", atenuar el pin si lleva >30 s sin actualizar en vez de esconderlo de golpe a los 90 s. | propuesta |
| F1.3 | **Precisión visible** | Círculo de error GPS + etiqueta "±8 m". | ✅ parcial (círculo solo propio) |
| F1.4 | **Expiración automática** | La posición se borra al salir (pagehide) y expira sola en 1 h (TTL `expireAt`). | ✅ hecho hoy |
| F1.5 | **Estados de llegada** | "Voy en camino / Ya llegué 🚩" — un toque, se ve en el pin de todos. Útil sobre todo en la junta. | propuesta |
| F1.6 | **Ritmo adaptativo** | Si no te mueves, escribir cada 10 s en vez de cada 1,2 s (batería y cuota Firestore). Si te mueves rápido, volver a 1,2 s. | propuesta |
| F1.7 | **Salir de la sala** | Botón explícito "salir" que borra tu doc y te lleva a la landing. Hoy solo cierras la pestaña. | propuesta |

## 2. Marcar la ubicación bien

| ID | Función | Detalle | Estado |
|---|---|---|---|
| F2.1 | **Crosshair para el pin propio** | Mira central + barra "📍 Estoy aquí / Cancelar" en `index.html`; el doble-tap queda como atajo. | ✅ hecho |
| F2.2 | **Zoom adaptativo** | Al acercarse dos personas (<50 m), subir el zoom solo y mostrar barra de escala en metros. | propuesta |
| F2.3 | Volver a GPS / deshacer el pin manual | Botón "Usar mi GPS". | ✅ existe |
| F2.4 | **Distinción clara** "yo estoy aquí" vs "la junta es allá" | Colores/íconos ya distintos (pin rosado vs bandera 🚩); mantener esta separación en todo lo nuevo. | ✅ existe |
| F2.5 | **Buscar lugar por nombre** | Campo de búsqueda (Nominatim gratis) para saltar el mapa a "Movistar Arena" y afinar a mano desde ahí. | propuesta |

## 3. La Junta con roles y permisos (el núcleo de esta iteración)

### Roles

- **Creador (admin):** quien fija la junta por primera vez en esa sala.
- **Editor:** miembro al que el admin le dio permiso de mover/cambiar hora.
- **Miembro:** ve todo, comparte su ubicación, propone cambios; no edita.

### Funciones

| ID | Función | Detalle | Prioridad propuesta |
|---|---|---|---|
| F3.1 | **El creador queda como admin** | Al crear la junta se guarda `ownerUid`. Su pin lleva 👑. | ✅ hecho |
| F3.2 | **Solo el admin mueve la junta / cambia la hora** (por defecto) | Los demás ven "🔒 Pedir mover" con el motivo "Solo Nacho puede mover la junta". Reglas de Firestore lo hacen cumplir de verdad. | ✅ hecho |
| F3.3 | **Política de edición configurable** | Panel 🔑: `solo yo` / `yo + editores` / `todos`. Cambio visible en el historial y en un chip permanente. | ✅ hecho |
| F3.4 | **Dar/quitar permiso a personas** | Lista de miembros con checkbox en el panel 🔑. | ✅ hecho |
| F3.5 | **Proponer cambio** | Versión lite hecha ✅: "pedir mover" avisa al admin (toast + historial). La versión completa (punto propuesto en el mapa + aceptar/rechazar) queda para después. | lite ✅ |
| F3.6 | **Traspaso / herencia de admin** | El admin puede traspasar el rol. Y si desaparece (cierra y no vuelve): tras X horas sin admin activo, ¿la junta pasa a `todos` o al miembro más antiguo? → **pregunta abierta P1**. | Should |
| F3.7 | **Historial con contexto** | Ya existe ✅; agregar los eventos de permisos ("Nacho dejó que todos editen"). | Should |
| F3.8 | Expulsar/bloquear a alguien de la sala | Sin cuentas reales es débil (vuelve con otro uid). | Won't (por ahora) |
| F3.9 | Varias juntas por sala ("punto A / plan B") | Complejidad de UI alta. | Won't (por ahora) |

### Modelo de datos propuesto

```
salas/{sala}/junta/actual {
  lat, lng, when, title,
  ownerUid,                       // F3.1
  policy: "owner"|"editors"|"all", // F3.3 (default: "owner")
  editors: [uid, ...],            // F3.4
  by, byUid, t, ts, expireAt
}
salas/{sala}/junta/actual/propuestas/{id} {   // F3.5
  lat?, lng?, when?, by, byUid, t, estado: "pendiente"|"aceptada"|"rechazada"
}
```

### ⚠️ La verdad incómoda: sin autenticación, los roles son solo decoración

Hoy el `uid` vive en `localStorage` y las reglas de Firestore están abiertas: cualquiera con la
consola del navegador puede escribir como si fuera el admin. Para que F3.2 sea **real** se
necesita:

1. **Firebase Anonymous Auth** — invisible para el usuario (cero registro, cero fricción): el
   navegador obtiene un `request.auth.uid` que no se puede falsificar.
2. **Reglas de Firestore** que lo usen. Boceto:

```
match /salas/{sala}/junta/actual {
  allow read: if request.auth != null;
  allow create: if request.auth != null
                && request.resource.data.ownerUid == request.auth.uid;
  allow update: if request.auth != null && (
       resource.data.policy == "all"
    || request.auth.uid == resource.data.ownerUid
    || (resource.data.policy == "editors" && request.auth.uid in resource.data.editors)
  );
}
match /salas/{sala}/miembros/{uid} {
  allow read: if request.auth != null;
  allow write: if request.auth.uid == uid
               && request.resource.data.keys().hasOnly(["name","lat","lng","acc","precise","ts","t","expireAt"]);
}
```

Esto además cierra el hoyo de seguridad general (hoy cualquiera puede leer/escribir toda sala) y
cumple el privacy-by-design de la Ley 21.719. **Recomendación: Anonymous Auth entra junto con
F3.1–F3.4, no después** — es lo que convierte los permisos en permisos.

## 4. Orden de implementación

1. **Ronda 1 (roles reales)** ✅ hecha (2026-08-06): Anonymous Auth + reglas nuevas + F3.1–F3.4
   + F2.1 (crosshair del pin propio) + F3.5 lite ("pedir mover" con aviso) + P1 (liberación a las 24 h).
2. **Ronda 2 (fluidez):** Google Sign-In para conservar identidad (P5), F1.5 (llegué),
   F1.2 (visto hace X), F1.7 (salir de la sala).
3. **Ronda 3 (pulido):** F3.6 (traspaso manual de admin), F1.6 (ritmo adaptativo), F2.2, F2.5,
   F3.7 ampliado, mapa de calor (idea P4).

> Nota: las reglas nuevas exigen sesión → la app Flutter (`pair/`, en pausa) quedó sin acceso a
> Firestore hasta que adopte Anonymous Auth.

## 5. Decisiones tomadas (2026-08-06)

- **P1 — Admin desaparecido → liberar con aviso, a las 24 h.** ✅ Implementado: si nadie con
  permiso edita la junta en 24 h, cualquiera puede editarla y el primero que lo hace queda como
  nuevo organizador (el historial registra "reclamó la junta · organizador inactivo 👑"). 24 h
  encaja bien: cubre "se le murió el teléfono en el evento" sin dejar la junta secuestrada, y está
  muy por debajo de los 30 días del TTL que borra juntas abandonadas.
- **P2 — Default `solo yo`.** ✅ Implementado. En vez de un botón de primer uso, hay un **chip
  permanente** visible para el admin ("🔒 solo tú · toca para cambiar") que abre el panel de
  permisos — siempre descubrible, no solo la primera vez.
- **P3 — El admin siempre existe y configura, sin importar el tamaño del grupo.** ✅ Así quedó:
  quien fija la junta es organizador; el panel 🔑 permite `solo yo` / `yo + elegidos` / `todos`.
- **P4 — Aviso "quiere mover" sí; propuestas formales no (por ahora).** ✅ Implementado lite:
  quien no tiene permiso ve "🔒 Pedir mover"; al tocarlo, al organizador le llega un toast
  ("Fran quiere mover la junta 🙋") y queda en el historial. La coordinación fina sigue por
  WhatsApp. **Mapa de calor:** anotado como idea futura (Could, ronda 3+) — no es complejo de
  dibujar, pero solo aporta con grupos grandes; se evalúa cuando haya uso real.
- **P5 — Que la identidad no se pierda → Google Sign-In en Ronda 2.** Pendiente: botón opcional
  "Guardar mi identidad con Google" que **vincula** la sesión anónima a la cuenta Google
  (`linkWithPopup`), conservando el mismo uid. Así el rol de organizador sobrevive a borrar el
  navegador. Requiere habilitar el proveedor Google en la consola de Firebase.
