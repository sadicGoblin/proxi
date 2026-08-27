// Proxi — núcleo compartido entre index.html y junta.html:
// Firebase, identidad (anónima o Google), perfil, mapas base y presencia en vivo.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, onAuthStateChanged, signInAnonymously, signOut,
         GoogleAuthProvider, linkWithPopup, linkWithRedirect,
         signInWithCredential, getRedirectResult }
  from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
import { getFirestore, doc, setDoc, deleteDoc, serverTimestamp, Timestamp }
  from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyCiqAsxD7_Me22aGHT9SO_AnRkJFyC5Xaw",
  authDomain: "proxi-live.firebaseapp.com",
  projectId: "proxi-live",
  storageBucket: "proxi-live.firebasestorage.app",
  messagingSenderId: "188965732831",
  appId: "1:188965732831:web:dd1eced1c6ce771c1ac46a"
};
const app = initializeApp(firebaseConfig);
export const db = getFirestore(app);
const auth = getAuth(app);

// Identidad real: sesión anónima de Firebase Auth (cero fricción), que el usuario
// puede vincular a Google desde su perfil. Vincular conserva el mismo uid, así que
// el rol de organizador de la junta no se pierde.
// El uid no se puede falsificar y es el que exigen las reglas de Firestore.
export async function ensureAuth(){
  // Si venimos de un login con redirección (fallback móvil), resolverlo primero.
  try{ await getRedirectResult(auth); }
  catch(err){
    if(err && err.code === "auth/credential-already-in-use"){
      // Esa cuenta Google ya existía: entrar con ella (el uid pasa a ser el de esa cuenta).
      const cred = GoogleAuthProvider.credentialFromError(err);
      if(cred) await signInWithCredential(auth, cred).catch(()=>{});
    }
  }
  return new Promise((resolve, reject) => {
    const stop = onAuthStateChanged(auth, u => {
      if(u){ stop(); resolve(u.uid); }
      else signInAnonymously(auth).catch(err => { stop(); reject(err); });
    }, reject);
  });
}

// Frescura de posiciones: hasta STALE_MS se muestran normal; entre STALE_MS y
// GONE_MS se muestran atenuadas con "hace X min" (típico: teléfono bloqueado);
// después desaparecen. Los docs llevan `expireAt` para el TTL de Firestore.
export const STALE_MS = 90_000;
export const GONE_MS = 10 * 60_000;
const PRESENCE_TTL_MS = 60 * 60_000;   // 1 h: una posición huérfana no vive más que eso

export const rnd = n => Array.from({length:n}, () => "abcdefghjkmnpqrstuvwxyz23456789"[Math.floor(Math.random()*30)]).join("");

export const esc = s => String(s||"").replace(/[<>&"]/g, c => ({"<":"&lt;",">":"&gt;","&":"&amp;",'"':"&quot;"}[c]));

// Solo se aceptan URLs https simples: la foto viaja por Firestore y termina dentro
// de un url('…') en el HTML del marcador, así que nada de comillas ni paréntesis.
const safeUrl = u => (typeof u === "string" && u.length <= 300
  && /^https:\/\/[A-Za-z0-9\-._~:/?#%&=+]+$/.test(u)) ? u : null;
export const photoOf = m => safeUrl(m && m.photo);

export function haversine(a,b,c,d){ const R=6371000,rad=x=>x*Math.PI/180;
  const dLat=rad(c-a),dLng=rad(d-b); const s=Math.sin(dLat/2)**2+Math.cos(rad(a))*Math.cos(rad(c))*Math.sin(dLng/2)**2;
  return 2*R*Math.asin(Math.sqrt(s)); }

// Timestamp de expiración para la política TTL de Firestore.
export const expireAt = ms => Timestamp.fromMillis(Date.now() + ms);

// ── Mapa (MapLibre GL: rota con 2 dedos, inclina, zoom fluido) ───────────────
// Las 5 bases raster van en un solo estilo y se alternan por visibilidad;
// la elegida se recuerda entre visitas y entre las dos páginas.
const BASES = {
  "Callejero": { tiles:["https://tile.openstreetmap.org/{z}/{x}/{y}.png"], max:19, attr:"© OpenStreetMap" },
  "Satélite":  { tiles:["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"], max:19, attr:"Imagery © Esri" },
  "Claro":     { tiles:["a","b","c","d"].map(s => `https://${s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png`), max:20, attr:"© OpenStreetMap, © CARTO" },
  "Oscuro":    { tiles:["a","b","c","d"].map(s => `https://${s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png`), max:20, attr:"© OpenStreetMap, © CARTO" },
  "Relieve":   { tiles:["https://server.arcgisonline.com/ArcGIS/rest/services/World_Shaded_Relief/MapServer/tile/{z}/{y}/{x}"], max:13, attr:"Relieve © Esri" },
};

export function createMap(container){
  const style = { version:8, sources:{}, layers:[
    { id:"bg", type:"background", paint:{ "background-color":"#0b0e1a" } } ] };
  for(const [name, b] of Object.entries(BASES)){
    style.sources["src-" + name] = { type:"raster", tiles:b.tiles, tileSize:256, maxzoom:b.max, attribution:b.attr };
    style.layers.push({ id:"base-" + name, type:"raster", source:"src-" + name, layout:{ visibility:"none" } });
  }
  const saved = localStorage.getItem("proxi_basemap");
  let current = BASES[saved] ? saved : "Callejero";
  style.layers.find(l => l.id === "base-" + current).layout.visibility = "visible";

  const map = new maplibregl.Map({
    container, style,
    center:[-70.6693, -33.4489], zoom:3, maxZoom:22,
    attributionControl:{ compact:true }
  });
  map.doubleClickZoom.disable();      // el doble clic/tap es acción de la app
  map.addControl(new maplibregl.NavigationControl({ visualizePitch:true }), "top-right");

  function pick(name){
    whenReady(map, () => {
      for(const n of Object.keys(BASES))
        map.setLayoutProperty("base-" + n, "visibility", n === name ? "visible" : "none");
    });
    current = name;
    localStorage.setItem("proxi_basemap", name);
  }
  // selector de estilo de mapa (control propio: MapLibre no trae uno)
  map.addControl({
    onAdd(){
      const c = document.createElement("div");
      c.className = "maplibregl-ctrl maplibregl-ctrl-group proxi-bases";
      const btn = document.createElement("button");
      btn.type = "button"; btn.textContent = "🗺"; btn.title = "Estilo de mapa";
      const list = document.createElement("div"); list.className = "list";
      for(const name of Object.keys(BASES)){
        const it = document.createElement("button");
        it.type = "button"; it.textContent = name;
        it.classList.toggle("on", name === current);
        it.addEventListener("click", () => {
          pick(name);
          list.querySelectorAll("button").forEach(x => x.classList.toggle("on", x === it));
          list.classList.remove("open");
        });
        list.appendChild(it);
      }
      btn.addEventListener("click", () => list.classList.toggle("open"));
      map.on("mousedown", () => list.classList.remove("open"));
      c.append(btn, list);
      return c;
    },
    onRemove(){}
  }, "top-right");
  return map;
}

function whenReady(map, fn){ if(map.isStyleLoaded()) fn(); else map.once("load", fn); }

// Dibuja o reemplaza una línea (coords como [[lat,lng],…]; dash en múltiplos del ancho).
export function setLine(map, id, latlngs, { color="#45c6f0", width=4, opacity=.9, dash=null } = {}){
  const geo = { type:"Feature", geometry:{ type:"LineString", coordinates: latlngs.map(c => [c[1], c[0]]) } };
  whenReady(map, () => {
    if(map.getLayer(id)) map.removeLayer(id);
    if(map.getSource(id)) map.removeSource(id);
    map.addSource(id, { type:"geojson", data:geo });
    map.addLayer({ id, type:"line", source:id,
      layout:{ "line-cap":"round", "line-join":"round" },
      paint:{ "line-color":color, "line-width":width, "line-opacity":opacity,
              ...(dash ? { "line-dasharray":dash } : {}) } });
  });
}
export function removeLine(map, id){
  whenReady(map, () => {
    if(map.getLayer(id)) map.removeLayer(id);
    if(map.getLayer(id + "-out")) map.removeLayer(id + "-out");
    if(map.getSource(id)) map.removeSource(id);
  });
}

// Círculo de precisión (radio en metros) como polígono relleno.
export function setCircle(map, id, lat, lng, radiusM, color = "#ff4d6d"){
  const ring = [];
  const dLat = radiusM / 111320, dLng = radiusM / (111320 * Math.cos(lat * Math.PI/180));
  for(let i = 0; i <= 64; i++){
    const a = 2 * Math.PI * i / 64;
    ring.push([lng + dLng * Math.cos(a), lat + dLat * Math.sin(a)]);
  }
  const geo = { type:"Feature", geometry:{ type:"Polygon", coordinates:[ring] } };
  whenReady(map, () => {
    const src = map.getSource(id);
    if(src){ src.setData(geo); return; }
    map.addSource(id, { type:"geojson", data:geo });
    map.addLayer({ id, type:"fill", source:id, paint:{ "fill-color":color, "fill-opacity":.08 } });
    map.addLayer({ id:id + "-out", type:"line", source:id, paint:{ "line-color":color, "line-width":1, "line-opacity":.5 } });
  });
}

// ── Ubicación robusta ────────────────────────────────────────────────────────
// watchPosition que se re-arma solo: al volver a la pestaña, al conceder el
// permiso desde el navegador, o manualmente (restart). Evita el clásico
// "no pidió ubicación / dejó de actualizar hasta recargar".
export function watchLocation(onFix, onProblem){
  let watchId = null, lastFix = 0;
  function start(){
    if(!("geolocation" in navigator)){ if(onProblem) onProblem("unsupported"); return; }
    if(watchId != null) navigator.geolocation.clearWatch(watchId);
    watchId = navigator.geolocation.watchPosition(
      p => { lastFix = Date.now(); onFix(p); },
      e => { if(onProblem) onProblem(e.code === 1 ? "denied" : "error"); },
      { enableHighAccuracy:true, maximumAge:1000, timeout:20000 });
  }
  const revive = () => { if(Date.now() - lastFix > 15000) start(); };
  document.addEventListener("visibilitychange", () => { if(document.visibilityState === "visible") revive(); });
  addEventListener("pageshow", revive);
  if(navigator.permissions && navigator.permissions.query){
    navigator.permissions.query({ name:"geolocation" })
      .then(st => st.addEventListener("change", () => { if(st.state === "granted") start(); }))
      .catch(()=>{});
  }
  start();
  return { restart: start };
}

// ── Perfil: nombre + cuenta Google opcional ──────────────────────────────────
// Inyecta el modal de perfil y lo engancha al botón-avatar de la topbar.
// Devuelve { getName, getPhoto } para presencia y junta.
const NAME_KEY = "proxi_name";
const G_SVG = `<svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>`;
const G_HINT = "Con Google tu foto aparece en el mapa y tu rol de organizador no se pierde al borrar los datos del navegador.";

export function setupProfile({ btn, onChange }){
  document.body.insertAdjacentHTML("beforeend", `
  <div class="modal" id="profModal">
    <div class="card">
      <h3>Tu perfil</h3>
      <p>Así te ve el grupo en el mapa.</p>
      <div class="profrow">
        <div class="profav" id="profAv"></div>
        <input type="text" id="profName" maxlength="18" placeholder="Tu nombre" autocomplete="off" />
      </div>
      <button class="gbtn" id="profGoogle"></button>
      <p class="profmail" id="profMail"></p>
      <div class="acts"><button class="ok" id="profOk">Listo</button></div>
    </div>
  </div>`);

  const modal = document.getElementById("profModal"), av = document.getElementById("profAv"),
        nameIn = document.getElementById("profName"), gbtn = document.getElementById("profGoogle"),
        mail = document.getElementById("profMail");

  let name = localStorage.getItem(NAME_KEY) || ("Invitado-" + rnd(3));
  // Si ya hay sesión Google y el nombre sigue siendo el de invitado, adoptar el de Google.
  const u0 = auth.currentUser;
  if(u0 && !u0.isAnonymous && u0.displayName && /^Invitado-/.test(name))
    name = u0.displayName.trim().slice(0,18);
  localStorage.setItem(NAME_KEY, name);
  nameIn.value = name;

  const photo = () => { const u = auth.currentUser; return u && !u.isAnonymous ? safeUrl(u.photoURL) : null; };

  function paint(){
    const p = photo(), letter = (name.trim()[0] || "?").toUpperCase();
    for(const el of [btn, av]){
      el.style.backgroundImage = p ? `url('${p}')` : "";
      el.textContent = p ? "" : letter;
    }
    const u = auth.currentUser;
    if(u && !u.isAnonymous){
      gbtn.innerHTML = "Cerrar sesión de Google";
      gbtn.classList.add("out");
      mail.textContent = "Sesión: " + (u.email || u.displayName || "cuenta Google");
    } else {
      gbtn.innerHTML = G_SVG + "Continuar con Google";
      gbtn.classList.remove("out");
      mail.textContent = G_HINT;
    }
  }

  nameIn.addEventListener("input", () => {
    name = nameIn.value.trim() || ("Invitado-" + rnd(3));
    localStorage.setItem(NAME_KEY, name);
    paint();
    if(onChange) onChange();
  });

  gbtn.addEventListener("click", async () => {
    const u = auth.currentUser;
    if(u && !u.isAnonymous){
      await signOut(auth).catch(()=>{});
      location.reload();               // vuelve como anónimo con uid nuevo: re-enganchar todo
      return;
    }
    gbtn.disabled = true;
    try{
      const provider = new GoogleAuthProvider();
      let res;
      try{
        res = await linkWithPopup(u, provider);   // conserva el uid → conserva rol de organizador
      }catch(err){
        if(err.code === "auth/credential-already-in-use"){
          // Esta cuenta Google ya tiene su propio uid: entrar con ella y recargar.
          const cred = GoogleAuthProvider.credentialFromError(err);
          await signInWithCredential(auth, cred);
          location.reload();
          return;
        }
        if(err.code === "auth/popup-blocked" || err.code === "auth/operation-not-supported-in-this-environment"){
          await linkWithRedirect(u, provider);    // móvil sin popups: vuelve tras el login
          return;
        }
        if(err.code === "auth/popup-closed-by-user" || err.code === "auth/cancelled-popup-request") return;
        throw err;
      }
      if(/^Invitado-/.test(name) && res.user.displayName){
        name = res.user.displayName.trim().slice(0,18);
        localStorage.setItem(NAME_KEY, name);
        nameIn.value = name;
      }
      paint();
      if(onChange) onChange();
    }catch(err){
      mail.textContent = "No se pudo iniciar con Google · ¿está habilitado el proveedor en Firebase?";
    }finally{ gbtn.disabled = false; }
  });

  btn.addEventListener("click", () => { paint(); modal.classList.add("on"); });
  document.getElementById("profOk").addEventListener("click", () => modal.classList.remove("on"));
  modal.addEventListener("click", e => { if(e.target === modal) modal.classList.remove("on"); });

  paint();
  return { getName: () => name, getPhoto: photo };
}

// ── Presencia ────────────────────────────────────────────────────────────────
// Escribe mi posición con throttle, la marca con expireAt y la borra
// al salir (pagehide es lo más confiable en móvil; beforeunload es respaldo).
export function createPresence({ room, uid, getPos, getName, getPhoto, onOk, onErr }){
  const meDoc = doc(db, "salas", room, "miembros", uid);
  let lastPush = 0, pending = false;
  async function pushNow(){
    const pos = getPos(); if(!pos) return;
    const now = Date.now(); if(now - lastPush < 1200){ pending = true; return; }
    lastPush = now; pending = false;
    try{
      await setDoc(meDoc, {
        name: getName(), photo: getPhoto ? (getPhoto() || null) : null,
        lat: pos.lat, lng: pos.lng, acc: pos.acc, precise: !!pos.precise,
        ts: serverTimestamp(), t: now, expireAt: expireAt(PRESENCE_TTL_MS)
      });
      if(onOk) onOk();
    }catch(err){ if(onErr) onErr(err); }
  }
  setInterval(() => { if(pending) pushNow(); }, 1300);
  const bye = () => { try{ deleteDoc(meDoc); }catch(e){} };
  addEventListener("pagehide", bye);
  addEventListener("beforeunload", bye);
  // vuelta desde bfcache o desde segundo plano: reaparecer al tiro
  addEventListener("pageshow", () => { lastPush = 0; pushNow(); });
  document.addEventListener("visibilitychange", () => { if(document.visibilityState === "visible"){ lastPush = 0; pushNow(); } });
  return { pushNow };
}

// ── Grupos recientes ─────────────────────────────────────────────────────────
// Guarda las salas/juntas visitadas para volver a ellas desde la portada
// sin tener que buscar el link en WhatsApp.
const ROOMS_KEY = "proxi_rooms";
export function rememberRoom(type, room, label){
  try{
    let list = JSON.parse(localStorage.getItem(ROOMS_KEY) || "[]");
    const prev = list.find(r => r.t === type && r.s === room);
    list = list.filter(r => !(r.t === type && r.s === room));
    list.unshift({ t: type, s: room, label: String(label || (prev && prev.label) || "").slice(0, 40), at: Date.now() });
    localStorage.setItem(ROOMS_KEY, JSON.stringify(list.slice(0, 8)));
  }catch(e){}
}
export function recentRooms(){
  try{ return JSON.parse(localStorage.getItem(ROOMS_KEY) || "[]").filter(r => r && r.s); }
  catch(e){ return []; }
}

// Mantiene la pantalla encendida mientras Proxi está visible: si la pantalla se
// bloquea, el navegador congela la página y la posición deja de actualizarse.
// (Si el usuario bloquea a mano igual se congela; eso solo lo resuelve una app nativa.)
export function keepAwake(){
  if(!("wakeLock" in navigator)) return;
  const req = () => navigator.wakeLock.request("screen").catch(()=>{});
  req();
  document.addEventListener("visibilitychange", () => { if(document.visibilityState === "visible") req(); });
}

export function registerSW(){
  if("serviceWorker" in navigator)
    addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(()=>{}));
}
