// Proxi nativa — núcleo: Firebase (mismo proyecto que la web), identidad y helpers.
// La app habla con el MISMO Firestore que proxi-live.web.app: mismas salas,
// mismos links, mismas reglas. Un grupo puede mezclar gente en web y en app.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

// La app Android está registrada en el proyecto proxi-live: la config nativa
// vive en android/app/google-services.json (generada con `firebase apps:*`).
late final FirebaseFirestore db;

Future<String> initFirebase() async {
  await Firebase.initializeApp();
  db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  return user.uid;
}

// ── Google Sign-In ───────────────────────────────────────────────────────────
// Igual que la web: primero intenta VINCULAR la sesión anónima (conserva el
// uid → conserva rol de organizador); si la cuenta Google ya existía, entra
// con ella (uid nuevo). Devuelve el usuario, o null si el usuario canceló.
Future<User?> signInGoogle() async {
  final g = GoogleSignIn(scopes: ['email']);
  final acc = await g.signIn();
  if (acc == null) return null; // canceló el selector de cuenta
  final a = await acc.authentication;
  final cred = GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken);
  final auth = FirebaseAuth.instance;
  try {
    return (await auth.currentUser!.linkWithCredential(cred)).user;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'credential-already-in-use' ||
        e.code == 'email-already-in-use' ||
        e.code == 'provider-already-linked') {
      return (await auth.signInWithCredential(cred)).user;
    }
    rethrow;
  }
}

Future<void> signOutGoogle() async {
  try { await GoogleSignIn().signOut(); } catch (_) {}
  await FirebaseAuth.instance.signOut();
  await FirebaseAuth.instance.signInAnonymously(); // vuelve como invitado (uid nuevo)
}

// Foto de perfil apta para compartir en presencia (reglas: https y ≤300).
String? profilePhoto() {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null || u.isAnonymous) return null;
  final p = u.photoURL;
  if (p == null || !p.startsWith('https://') || p.length > 300) return null;
  return p;
}

// Mismo alfabeto de códigos de sala que la web (sin caracteres confusos).
const _alpha = 'abcdefghjkmnpqrstuvwxyz23456789';
String rnd(int n) {
  final r = Random();
  return List.generate(n, (_) => _alpha[r.nextInt(_alpha.length)]).join();
}

// Frescura de posiciones (idéntico a la web).
const staleMs = 90 * 1000; // hasta aquí se muestra normal
const goneMs = 10 * 60 * 1000; // después de esto desaparece del mapa

// Nombre del usuario, persistente.
Future<String> loadName() async {
  final p = await SharedPreferences.getInstance();
  var name = p.getString('proxi_name');
  if (name == null || name.trim().isEmpty) {
    name = 'Invitado-${rnd(3)}';
    await p.setString('proxi_name', name);
  }
  return name;
}

Future<void> saveName(String name) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('proxi_name', name.trim());
}

// Grupos recientes: [{s: código, at: epoch ms}] — para volver de un toque.
Future<List<Map<String, dynamic>>> recentRooms() async {
  final p = await SharedPreferences.getInstance();
  final codes = p.getStringList('proxi_rooms') ?? [];
  return codes.map((e) {
    final parts = e.split('|');
    return {'s': parts[0], 'at': parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0};
  }).toList();
}

Future<void> rememberRoom(String room) async {
  final p = await SharedPreferences.getInstance();
  final list = p.getStringList('proxi_rooms') ?? [];
  list.removeWhere((e) => e.split('|')[0] == room);
  list.insert(0, '$room|${DateTime.now().millisecondsSinceEpoch}');
  await p.setStringList('proxi_rooms', list.take(8).toList());
}

String agoTxt(int t) {
  final m = ((DateTime.now().millisecondsSinceEpoch - t) / 60000).round();
  if (m < 1) return 'recién';
  if (m < 60) return 'hace $m min';
  if (m < 1440) return 'hace ${(m / 60).round()} h';
  return 'hace ${(m / 1440).round()} días';
}
