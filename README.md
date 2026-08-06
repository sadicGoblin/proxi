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
gcloud firestore fields ttls update expireAt --collection-group=ruta     --enable-ttl --project=proxi-live
```

Mientras tanto el cliente ya ignora posiciones con más de 90 s de antigüedad, así que un doc
huérfano nunca se muestra aunque aún no se haya borrado.

## Autenticación (hacer una vez en la consola)

La app usa **Anonymous Auth** (sesión invisible, sin registro) y las reglas de Firestore la
exigen. Además, desde el perfil (avatar arriba a la derecha) el usuario puede **iniciar sesión
con Google** — opcional: su foto reemplaza el punto en el mapa y su rol de organizador
sobrevive a borrar los datos del navegador (se vincula a la sesión anónima conservando el uid).

Habilitar ambos proveedores una vez:
**Consola Firebase → proxi-live → Authentication → Sign-in method →**
1. **Anónimo → Habilitar** (sin esto, la app no puede conectarse a la base de datos).
2. **Google → Habilitar** (elige un correo de soporte y guarda). Sin esto, el botón
   "Continuar con Google" del perfil mostrará un error.

Los dominios `proxi-live.web.app`, `proxi-live.firebaseapp.com` y `localhost` ya vienen
autorizados por defecto; si sirves desde otro dominio, agrégalo en
**Authentication → Settings → Authorized domains**.

## Estado de seguridad

- [`firestore.rules`](firestore.rules): requieren sesión, validan esquema (incluida la foto de
  perfil: solo URL https corta) y hacen cumplir los roles de la junta (solo el organizador
  mueve, salvo que delegue; liberación a las 24 h de inactividad). Diseño y decisiones en
  [`JUNTA.md`](JUNTA.md).
- Ronda 2 (Google Sign-In opcional): ✅ hecha — vincular conserva el uid; si la cuenta Google
  ya existía, se entra con ella (uid nuevo) y la página se recarga.
- La app Flutter (`pair/`, en pausa) quedó sin acceso a Firestore hasta que adopte auth.
