// Proxi nativa — núcleo: Firebase (mismo proyecto que la web), identidad y helpers.
// La app habla con el MISMO Firestore que proxi-live.web.app: mismas salas,
// mismos links, mismas reglas. Un grupo puede mezclar gente en web y en app.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Config del proyecto proxi-live (la misma clave pública que usa la web).
// Nota: cuando registremos la app Android en la consola de Firebase
// (flutterfire configure), esto se reemplaza por las opciones propias.
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCiqAsxD7_Me22aGHT9SO_AnRkJFyC5Xaw',
  appId: '1:188965732831:web:dd1eced1c6ce771c1ac46a',
  messagingSenderId: '188965732831',
  projectId: 'proxi-live',
);

late final FirebaseFirestore db;

Future<String> initFirebase() async {
  await Firebase.initializeApp(options: firebaseOptions);
  db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  return user.uid;
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
