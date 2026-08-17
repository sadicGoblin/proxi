// Proxi — service worker: deja el "app shell" disponible offline y acelera cargas.
// Sube la versión al cambiar cualquier archivo del shell.
const CACHE = "proxi-v10";
const SHELL = [
  "/", "/index.html", "/junta.html", "/descargar.html",
  "/css/proxi.css", "/js/core.js",
  "/manifest.webmanifest", "/icons/icon.svg", "/icons/maskable.svg",
  "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css",
  "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if(req.method !== "GET") return;
  const u = new URL(req.url);

  // Firestore / Firebase en tiempo real: siempre red, nunca caché.
  if(u.hostname.endsWith("googleapis.com") || u.hostname.endsWith("gstatic.com")) return;

  // Navegaciones: red primero (contenido fresco), caché como respaldo offline.
  if(req.mode === "navigate"){
    e.respondWith(
      fetch(req).then(r => {
        const cp = r.clone(); caches.open(CACHE).then(c => c.put(req, cp));
        return r;
      }).catch(() =>
        caches.match(req, { ignoreSearch:true }).then(r => r || caches.match("/index.html"))
      )
    );
    return;
  }

  // Archivos grandes (APK antiguo): directo a red, sin caché.
  if(u.pathname.endsWith(".bin")) return;

  // Assets propios: RED primero, caché solo como respaldo offline.
  // (Caché-primero mezclaba HTML nuevo con JS/CSS viejos → página rota hasta el segundo F5.)
  if(u.origin === location.origin){
    e.respondWith(
      fetch(req).then(r => {
        if(r.ok){ const cp = r.clone(); caches.open(CACHE).then(c => c.put(req, cp)); }
        return r;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // CDN de Leaflet (URLs con versión fija): caché primero; teselas de mapa pasan directo a red.
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(r => {
      if(r.ok && u.hostname === "unpkg.com"){
        const cp = r.clone(); caches.open(CACHE).then(c => c.put(req, cp));
      }
      return r;
    }))
  );
});
