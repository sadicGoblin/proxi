// Proxi — núcleo compartido entre index.html y junta.html:
// Firebase, identidad, presencia en vivo y helpers.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
import { getAuth, onAuthStateChanged, signInAnonymously }
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

// Identidad real: sesión anónima de Firebase Auth (cero fricción para el usuario).
// El uid que devuelve no se puede falsificar y es el que exigen las reglas de Firestore.
// Persiste en el navegador hasta que el usuario borre los datos del sitio.
export function ensureAuth(){
  return new Promise((resolve, reject) => {
    const stop = onAuthStateChanged(auth, u => {
      if(u){ stop(); resolve(u.uid); }
      else signInAnonymously(auth).catch(err => { stop(); reject(err); });
    }, reject);
  });
}

// El cliente ignora posiciones más viejas que esto; además los docs llevan
// `expireAt` para que la política TTL de Firestore los borre sola (ver README).
export const STALE_MS = 90_000;
const PRESENCE_TTL_MS = 60 * 60_000;   // 1 h: una posición huérfana no vive más que eso

export const rnd = n => Array.from({length:n}, () => "abcdefghjkmnpqrstuvwxyz23456789"[Math.floor(Math.random()*30)]).join("");

// Devuelve un getter del nombre y mantiene el input y localStorage sincronizados.
export function initName(inputEl, uid, onChange){
  let name = localStorage.getItem("proxi_name") || ("Invitado-" + rnd(3));
  inputEl.value = name;
  inputEl.addEventListener("input", () => {
    name = inputEl.value.trim() || ("Invitado-" + uid.slice(0,3));
    localStorage.setItem("proxi_name", name);
    if(onChange) onChange(name);
  });
  return () => name;
}

export const esc = s => String(s||"").replace(/[<>&"]/g, c => ({"<":"&lt;",">":"&gt;","&":"&amp;",'"':"&quot;"}[c]));

export function haversine(a,b,c,d){ const R=6371000,rad=x=>x*Math.PI/180;
  const dLat=rad(c-a),dLng=rad(d-b); const s=Math.sin(dLat/2)**2+Math.cos(rad(a))*Math.cos(rad(c))*Math.sin(dLng/2)**2;
  return 2*R*Math.asin(Math.sqrt(s)); }

// Timestamp de expiración para la política TTL de Firestore.
export const expireAt = ms => Timestamp.fromMillis(Date.now() + ms);

// Presencia: escribe mi posición con throttle, la marca con expireAt y la borra
// al salir (pagehide es lo más confiable en móvil; beforeunload es respaldo).
export function createPresence({ room, uid, getPos, getName, onOk, onErr }){
  const meDoc = doc(db, "salas", room, "miembros", uid);
  let lastPush = 0, pending = false;
  async function pushNow(){
    const pos = getPos(); if(!pos) return;
    const now = Date.now(); if(now - lastPush < 1200){ pending = true; return; }
    lastPush = now; pending = false;
    try{
      await setDoc(meDoc, {
        name: getName(), lat: pos.lat, lng: pos.lng, acc: pos.acc, precise: !!pos.precise,
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

export function registerSW(){
  if("serviceWorker" in navigator)
    addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(()=>{}));
}
