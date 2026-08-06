# Proxi

> Encuéntrense exacto, incluso entre la multitud.

Web app para **compartir ubicación precisa en vivo** y fijar la **junta del grupo** (punto de
encuentro + hora compartidos). Sin instalar nada: se comparte un link y se abre en el navegador.

## Qué hay aquí

| Ruta | Qué es |
|---|---|
| [`public/`](public/) | La web app real (Firebase Hosting + Firestore) |
| [`public/index.html`](public/index.html) | Landing + **sala en vivo**: posiciones en tiempo real, pin manual exacto, flecha y distancia |
| [`public/junta.html`](public/junta.html) | **Junta del grupo**: punto + hora compartidos, cualquiera del grupo ve los cambios al instante |
| [`public/js/core.js`](public/js/core.js) | Núcleo compartido: Firebase, identidad, presencia con expiración |
| [`public/css/proxi.css`](public/css/proxi.css) | Estilos compartidos |
| [`public/sw.js`](public/sw.js) + [`public/manifest.webmanifest`](public/manifest.webmanifest) | PWA: instalable y con app shell offline |
| [`proxi_app/`](proxi_app/) | App Flutter (Android) — fase 2, en pausa |
| [`PLAN.md`](PLAN.md) | Plan de producto y roadmap |
| [`JUNTA.md`](JUNTA.md) | Spec en análisis: compartir bien, marcar bien y junta con roles/permisos |
| [`MODELO-NEGOCIO.md`](MODELO-NEGOCIO.md) | Modelo de negocio (B2B2C eventos, Chile/LatAm) |
| [`FARO.md`](FARO.md) / [`UWB.md`](UWB.md) / [`RECINTOS.md`](RECINTOS.md) | Investigación archivada (Faro fue probado y descartado) |

## Correr localmente

Los archivos de `public/` son estáticos; basta servirlos:

```bash
npx serve public
# o con el emulador de hosting:
firebase serve --only hosting
```

La app habla con el Firestore del proyecto `proxi-live` (config en `public/js/core.js`).

## Publicar (gratis, plan Spark)

```bash
npm install -g firebase-tools
firebase login
firebase deploy
```

Queda en `https://proxi-live.web.app`.

## Limpieza automática de datos (TTL) — hacer una vez

Los documentos de posición llevan un campo `expireAt` (1 h) y los de la junta también (30 días).
Para que Firestore los borre solo, habilita la política TTL una vez por grupo de colecciones
(consola → Firestore → TTL, o por CLI):

```bash
gcloud firestore fields ttls update expireAt --collection-group=miembros --enable-ttl --project=proxi-live
gcloud firestore fields ttls update expireAt --collection-group=junta    --enable-ttl --project=proxi-live
gcloud firestore fields ttls update expireAt --collection-group=cambios  --enable-ttl --project=proxi-live
```

Mientras tanto el cliente ya ignora posiciones con más de 90 s de antigüedad, así que un doc
huérfano nunca se muestra aunque aún no se haya borrado.

## Autenticación (hacer una vez en la consola)

La app usa **Anonymous Auth** (sesión invisible, sin registro) y las reglas de Firestore la
exigen. Habilitarla una vez:
**Consola Firebase → proxi-live → Authentication → Comenzar → Sign-in method → Anónimo → Habilitar.**
Sin esto, la app no puede conectarse a la base de datos.

## Estado de seguridad

- [`firestore.rules`](firestore.rules): requieren sesión, validan esquema y hacen cumplir los
  roles de la junta (solo el organizador mueve, salvo que delegue; liberación a las 24 h de
  inactividad). Diseño y decisiones en [`JUNTA.md`](JUNTA.md).
- Ronda 2 pendiente: Google Sign-In opcional para que el rol de organizador sobreviva a borrar
  los datos del navegador.
- La app Flutter (`pair/`, en pausa) quedó sin acceso a Firestore hasta que adopte auth.
