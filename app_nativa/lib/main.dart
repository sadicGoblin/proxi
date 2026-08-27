// Proxi nativa — la diferencia con la web/APK-TWA: ubicación en segundo plano
// (te siguen viendo llegar con la pantalla bloqueada), y pronto notificaciones.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core.dart';
import 'sala_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final uid = await initFirebase();
  runApp(ProxiApp(uid: uid));
}

const kBg = Color(0xFF0B0E1A);
const kSurface = Color(0xFF12172A);
const kSurface2 = Color(0xFF1A2039);
const kYou = Color(0xFFFF4D6D);
const kFriend = Color(0xFF45C6F0);
const kFlag = Color(0xFFFFD166);
const kMute = Color(0xFF8E94B0);

class ProxiApp extends StatelessWidget {
  const ProxiApp({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kYou,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(uid: uid),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.uid});
  final String uid;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameCtl = TextEditingController();
  final _roomCtl = TextEditingController();
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    loadName().then((n) => setState(() => _nameCtl.text = n));
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final r = await recentRooms();
    if (mounted) setState(() => _recent = r);
  }

  Future<void> _open(String room) async {
    room = room.trim().toLowerCase();
    if (room.isEmpty) return;
    await saveName(_nameCtl.text.trim().isEmpty ? 'Invitado-${rnd(3)}' : _nameCtl.text.trim());
    await rememberRoom(room);
    if (!mounted) return;
    // uid vigente: puede haber cambiado si entraste con una cuenta Google previa
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.uid;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SalaScreen(uid: uid, room: room)),
    );
    _loadRecent();
  }

  Future<void> _google() async {
    try {
      final u = await signInGoogle();
      if (u == null) return; // canceló
      // adopta el nombre de Google si aún usas el de invitado (igual que la web)
      if (_nameCtl.text.startsWith('Invitado-') && (u.displayName ?? '').isNotEmpty) {
        final n = u.displayName!.trim();
        _nameCtl.text = n.length > 18 ? n.substring(0, 18) : n;
        await saveName(_nameCtl.text);
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo iniciar con Google · revisa tu conexión')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            const Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Prox', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                TextSpan(text: 'i', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: kYou)),
              ]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Encuéntrense exacto, incluso entre la multitud.\nEsta app te sigue compartiendo aunque bloquees la pantalla.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMute, height: 1.5),
            ),
            const SizedBox(height: 26),
            TextField(
              controller: _nameCtl,
              maxLength: 18,
              decoration: _dec('Tu nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _roomCtl,
              maxLength: 12,
              decoration: _dec('Código del grupo (ej: k7m2p)'),
              onSubmitted: _open,
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kYou,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => _open(_roomCtl.text),
              child: const Text('Entrar al grupo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: kSurface2),
              ),
              onPressed: () => _open(rnd(5)),
              child: const Text('📍 Crear grupo nuevo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white)),
            ),
            const SizedBox(height: 8),
            _googleSection(),
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text('TUS GRUPOS RECIENTES',
                  style: TextStyle(color: kMute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              for (final r in _recent)
                Card(
                  color: kSurface2,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Text('📍', style: TextStyle(fontSize: 20)),
                    title: Text(r['s'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: Text(agoTxt(r['at'] as int), style: const TextStyle(color: kMute, fontSize: 12)),
                    onTap: () => _open(r['s'] as String),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Los códigos son los mismos de proxi-live.web.app:\nun grupo puede mezclar gente en la web y en la app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMute, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // Con Google tu foto aparece en el mapa (también para quienes usan la web)
  // y tu rol de organizador no se pierde al reinstalar.
  Widget _googleSection() {
    final u = FirebaseAuth.instance.currentUser;
    final logged = u != null && !u.isAnonymous;
    if (!logged) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        onPressed: _google,
        icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
        label: const Text('Continuar con Google', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
    }
    final photo = profilePhoto();
    return Card(
      color: kSurface2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: kSurface,
          backgroundImage: photo != null ? NetworkImage(photo) : null,
          child: photo == null ? Text((_nameCtl.text.isNotEmpty ? _nameCtl.text[0] : '?').toUpperCase()) : null,
        ),
        title: Text(u.displayName ?? 'Cuenta Google', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(u.email ?? '', style: const TextStyle(color: kMute, fontSize: 12)),
        trailing: TextButton(
          onPressed: () async { await signOutGoogle(); setState(() {}); },
          child: const Text('Salir', style: TextStyle(color: kMute)),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: kSurface2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );
}
