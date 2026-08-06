import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:torch_light/torch_light.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'services/uwb_service.dart';
import 'services/ble_proximity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProxiApp());
}

const kYou = Color(0xFFFF4D6D);
const kFriend = Color(0xFF45C6F0);
const kBg = Color(0xFF0B0E1A);
const kSurface = Color(0xFF12172A);

// Paleta "Faro": colores raros en un concierto (evita blanco/ámbar de linternas y light-show).
const kFaro = <Map<String, dynamic>>[
  {'name': 'CIAN', 'color': Color(0xFF00E5FF)},
  {'name': 'MAGENTA', 'color': Color(0xFFFF2BD6)},
  {'name': 'LIMA', 'color': Color(0xFFB6FF00)},
];

class ProxiApp extends StatelessWidget {
  const ProxiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proxi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: kBg),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _db = FirebaseFirestore.instance;
  final _uwb = UwbService();
  final _map = MapController();
  final _rnd = Random();

  late final String _uid;
  final String _room = 'prueba';
  late final String _name;

  LatLng? _me;
  double _acc = 30;
  bool _centered = false;
  final Map<String, Map<String, dynamic>> _members = {};

  bool _uwbAvailable = false;
  double? _uwbDist;
  double? _uwbAz;
  bool _pairingStarted = false;

  // ---- Bluetooth "caliente/frío" ----
  final _ble = BleProximity();
  int? _bleRssi;
  double? _bleMeters;
  double? _lastBleMeters;
  String _bleTrend = '';

  // ---- Faro ----
  bool _beaconActive = false; // yo soy la baliza (me están buscando)
  bool _beaconOn = false; // estado del parpadeo
  Color _beaconColor = const Color(0xFF00E5FF);
  String _beaconColorName = '';
  int _beaconStep = 0;
  Timer? _beaconTimer;
  // patrón: 3 destellos + pausa
  static const List<bool> _pattern = [true, false, true, false, true, false, false, false];

  bool _seeking = false; // yo estoy buscando (pedí que se ilumine)
  Color _seekColor = const Color(0xFF00E5FF);
  String _seekColorName = '';
  String? _seekTarget;

  StreamSubscription? _posSub, _memSub, _pairSub, _uwbSub, _faroSub, _seekSub, _bleSub;

  @override
  void initState() {
    super.initState();
    _uid = _randId(6);
    _name = 'Equipo-${_uid.substring(0, 3)}';
    _uwbSub = _uwb.samples.listen(_onUwbSample);
    _initUwb();
    _initLocation();
    _listenMembers();
    _listenFaro();
    _startBle();
  }

  Future<void> _startBle() async {
    _bleSub = _ble.samples.listen(_onBle);
    await _ble.start();
  }

  void _onBle(BleSample s) {
    if (!mounted) return;
    setState(() {
      if (_lastBleMeters != null) {
        if (s.meters < _lastBleMeters! - 0.4) {
          _bleTrend = 'te acercas';
        } else if (s.meters > _lastBleMeters! + 0.4) {
          _bleTrend = 'te alejas';
        }
      }
      _bleRssi = s.rssi;
      _bleMeters = s.meters;
      _lastBleMeters = s.meters;
    });
  }

  String _randId(int n) =>
      List.generate(n, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[_rnd.nextInt(30)]).join();
  List<int> _randBytes(int n) => List.generate(n, (_) => _rnd.nextInt(256));

  Future<void> _initUwb() async {
    final ok = await _uwb.isAvailable();
    setState(() => _uwbAvailable = ok);
    _writeMember();
  }

  Future<void> _initLocation() async {
    await Geolocator.requestPermission();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((p) {
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _acc = p.accuracy;
      });
      _writeMember();
      if (!_centered && _me != null) {
        _centered = true;
        _map.move(_me!, 18);
      }
    });
  }

  void _writeMember() {
    if (_me == null) return;
    _db.collection('salas').doc(_room).collection('miembros').doc(_uid).set({
      'name': _name,
      'lat': _me!.latitude,
      'lng': _me!.longitude,
      'acc': _acc,
      'uwb': _uwbAvailable,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _listenMembers() {
    _memSub = _db.collection('salas').doc(_room).collection('miembros').snapshots().listen((snap) {
      _members
        ..clear()
        ..addEntries(snap.docs.map((d) => MapEntry(d.id, d.data())));
      setState(() {});
      _maybeStartUwb();
    });
  }

  MapEntry<String, Map<String, dynamic>>? _otherMember() {
    final others = _members.entries.where((e) => e.key != _uid);
    return others.isEmpty ? null : others.first;
  }

  String _otherName() => _otherMember()?.value['name']?.toString() ?? 'tu contacto';

  // ============ UWB (capa premium; solo si ambos tienen chip) ============
  Future<void> _maybeStartUwb() async {
    if (_pairingStarted || !_uwbAvailable) return;
    final other = _otherMember();
    if (other == null || other.value['uwb'] != true) return;
    _pairingStarted = true;
    if (_uid.compareTo(other.key) < 0) {
      await _startController();
    } else {
      await _startControlee();
    }
  }

  DocumentReference<Map<String, dynamic>> get _pairDoc =>
      _db.collection('salas').doc(_room).collection('pair').doc('session');

  Future<void> _startController() async {
    final info = await _uwb.prepareController();
    final sessionId = _rnd.nextInt(0x7fffffff);
    final key = _randBytes(8);
    await _pairDoc.set({
      'controllerUid': _uid,
      'controllerAddress': info['address'],
      'channel': info['channel'],
      'preamble': info['preamble'],
      'sessionId': sessionId,
      'sessionKey': key,
    }, SetOptions(merge: true));
    _pairSub = _pairDoc.snapshots().listen((snap) async {
      final peer = snap.data()?['controleeAddress'];
      if (peer is List) {
        await _pairSub?.cancel();
        await _uwb.startRanging(
          role: 'controller',
          peerAddress: peer.cast<int>(),
          sessionId: sessionId,
          sessionKey: key,
          channel: info['channel'] as int,
          preamble: info['preamble'] as int,
        );
      }
    });
  }

  Future<void> _startControlee() async {
    final info = await _uwb.prepareControlee();
    await _pairDoc.set({'controleeUid': _uid, 'controleeAddress': info['address']}, SetOptions(merge: true));
    _pairSub = _pairDoc.snapshots().listen((snap) async {
      final d = snap.data();
      if (d != null && d['controllerAddress'] is List && d['sessionId'] != null) {
        await _pairSub?.cancel();
        await _uwb.startRanging(
          role: 'controlee',
          peerAddress: (d['controllerAddress'] as List).cast<int>(),
          sessionId: d['sessionId'] as int,
          sessionKey: (d['sessionKey'] as List).cast<int>(),
          channel: d['channel'] as int,
          preamble: d['preamble'] as int,
        );
      }
    });
  }

  void _onUwbSample(UwbSample s) {
    if (!mounted) return;
    setState(() {
      if (s.type == 'position') {
        _uwbDist = s.distance;
        _uwbAz = s.azimuth;
      }
    });
  }

  // ============ FARO (baliza óptica — el mecanismo estrella) ============
  DocumentReference<Map<String, dynamic>> _faroDoc(String uid) =>
      _db.collection('salas').doc(_room).collection('faro').doc(uid);

  void _listenFaro() {
    // escucho MI documento: si alguien me pide iluminarme, parpadeo.
    _faroSub = _faroDoc(_uid).snapshots().listen((s) {
      final d = s.data();
      if (d != null && d['active'] == true) {
        _startBeacon(Color(d['color'] as int? ?? 0xFF00E5FF), d['colorName'] as String? ?? '');
      } else {
        _stopBeacon();
      }
    });
  }

  Future<void> _setTorch(bool on) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
    } catch (_) {/* sin flash (emulador) → solo pantalla */}
  }

  Future<void> _setBrightness(double? v) async {
    try {
      if (v == null) {
        await ScreenBrightness().resetApplicationScreenBrightness();
      } else {
        await ScreenBrightness().setApplicationScreenBrightness(v);
      }
    } catch (_) {}
  }

  void _startBeacon(Color color, String name) {
    if (_beaconActive) {
      setState(() {
        _beaconColor = color;
        _beaconColorName = name;
      });
      return;
    }
    setState(() {
      _beaconActive = true;
      _beaconColor = color;
      _beaconColorName = name;
      _beaconOn = true;
      _beaconStep = 0;
    });
    _setBrightness(1.0);
    _beaconTimer = Timer.periodic(const Duration(milliseconds: 170), (_) {
      final on = _pattern[_beaconStep % _pattern.length];
      _beaconStep++;
      if (mounted) {
        setState(() => _beaconOn = on);
      }
      _setTorch(on);
    });
  }

  void _stopBeacon() {
    if (!_beaconActive && _beaconTimer == null) return;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _setTorch(false);
    _setBrightness(null);
    if (mounted) {
      setState(() {
        _beaconActive = false;
        _beaconOn = false;
      });
    }
  }

  // yo (buscado) confirmo que me encontraron → apago mi baliza
  void _foundMe() => _faroDoc(_uid).set({'active': false}, SetOptions(merge: true));

  // yo (buscador) pido a la otra persona que se ilumine
  void _askIlluminate() {
    final other = _otherMember();
    if (other == null) return;
    final pick = kFaro[_rnd.nextInt(kFaro.length)];
    final target = other.key;
    _faroDoc(target).set({
      'active': true,
      'color': (pick['color'] as Color).toARGB32(),
      'colorName': pick['name'],
      'by': _uid,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    setState(() {
      _seeking = true;
      _seekColor = pick['color'] as Color;
      _seekColorName = pick['name'] as String;
      _seekTarget = target;
    });
    // observo el mismo doc: si la baliza se apaga (la encontraron), cierro la búsqueda.
    _seekSub?.cancel();
    _seekSub = _faroDoc(target).snapshots().listen((s) {
      final d = s.data();
      if (d == null || d['active'] != true) _stopSeeking();
    });
  }

  void _iSeeThem() {
    if (_seekTarget != null) {
      _faroDoc(_seekTarget!).set({'active': false}, SetOptions(merge: true));
    }
    _stopSeeking();
  }

  void _stopSeeking() {
    _seekSub?.cancel();
    _seekSub = null;
    if (mounted) {
      setState(() => _seeking = false);
    }
  }

  double? _gpsDist() {
    final other = _otherMember();
    if (_me == null || other == null || other.value['lat'] == null) return null;
    return Geolocator.distanceBetween(
      _me!.latitude, _me!.longitude,
      (other.value['lat'] as num).toDouble(), (other.value['lng'] as num).toDouble(),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _memSub?.cancel();
    _pairSub?.cancel();
    _uwbSub?.cancel();
    _faroSub?.cancel();
    _seekSub?.cancel();
    _bleSub?.cancel();
    _beaconTimer?.cancel();
    _setTorch(false);
    _setBrightness(null);
    _ble.stop();
    _uwb.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si me están buscando, la pantalla ENTERA es la baliza.
    if (_beaconActive) return _beaconScreen();

    final markers = <Marker>[];
    _members.forEach((id, m) {
      if (m['lat'] == null) return;
      final isMe = id == _uid;
      markers.add(Marker(
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        width: 90,
        height: 54,
        child: _PinLabel(isMe: isMe, label: isMe ? 'tú' : (m['name']?.toString() ?? 'amigo')),
      ));
    });

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: LatLng(-33.4489, -70.6693),
              initialZoom: 3,
              maxZoom: 22,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.favric.proxi_app',
                maxNativeZoom: 19,
                maxZoom: 22,
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kBg.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Text('Proxi · sala "$_room"',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _seeking ? _seekingPanel() : _panel()),
        ],
      ),
    );
  }

  // pantalla-baliza (buscado): parpadea el color asignado a pantalla completa
  Widget _beaconScreen() {
    final onText = _beaconOn ? Colors.black87 : Colors.white;
    return Scaffold(
      backgroundColor: _beaconOn ? _beaconColor : Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(Icons.wb_iridescent, size: 92, color: onText),
              const SizedBox(height: 18),
              Text('TE ESTÁN BUSCANDO',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: onText, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 10),
              Text('Levanta el teléfono en alto 🙌\nEstás brillando en ${_beaconColorName.toLowerCase()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: onText.withValues(alpha: 0.85), fontSize: 15)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _foundMe,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.85),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Ya me encontraron', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // panel del buscador mientras la otra persona se ilumina
  Widget _seekingPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: _seekColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: _seekColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: _seekColor.withValues(alpha: 0.7), blurRadius: 18)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Busca el destello $_seekColorName',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${_otherName()} está parpadeando · 3 destellos. Levanta la vista y búscalo.',
                        style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _iSeeThem,
              style: FilledButton.styleFrom(backgroundColor: kFriend, padding: const EdgeInsets.symmetric(vertical: 15)),
              child: const Text('¡Lo veo! 👀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  // termómetro "caliente/frío" por Bluetooth
  Widget _bleBar() {
    final rssi = _bleRssi ?? -100;
    final heat = ((rssi + 95) / 45).clamp(0.0, 1.0);
    final band = rssi > -60
        ? 'MUY CERCA'
        : rssi > -72
            ? 'CERCA'
            : rssi > -82
                ? 'TIBIO'
                : 'LEJOS';
    final color = Color.lerp(kFriend, kYou, heat)!;
    final trendColor = _bleTrend == 'te acercas'
        ? const Color(0xFF5FD08A)
        : _bleTrend == 'te alejas'
            ? const Color(0xFFF2B25C)
            : Colors.white54;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Bluetooth', style: TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(band, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_bleTrend.isNotEmpty)
                Text(_bleTrend, style: TextStyle(color: trendColor, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('~${_bleMeters!.toStringAsFixed(1)} m',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: heat,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    final uwbOn = _uwbDist != null;
    final gps = _gpsDist();
    final other = _otherMember();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 38, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
          Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (uwbOn ? kYou : Colors.white10).withValues(alpha: 0.14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Transform.rotate(
                  angle: (_uwbAz ?? 0) * pi / 180,
                  child: Icon(Icons.navigation, color: uwbOn ? kYou : Colors.white24, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(other == null ? 'Esperando al otro equipo…' : _otherName(),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(uwbOn ? 'UWB · precisión de centímetros' : 'GPS aproximado',
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    uwbOn
                        ? _uwbDist!.toStringAsFixed(2)
                        : (gps == null ? '—' : (gps < 10 ? gps.toStringAsFixed(1) : gps.round().toString())),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1, color: uwbOn ? kYou : Colors.white),
                  ),
                  const SizedBox(height: 3),
                  Text(uwbOn ? 'm · UWB' : 'm · GPS', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ],
          ),
          if (_bleMeters != null) _bleBar(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: other == null ? null : _askIlluminate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                disabledBackgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: const Icon(Icons.flashlight_on, color: Colors.black),
              label: Text(
                other == null ? 'Esperando a alguien…' : 'Pídele que se ilumine',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Faro: la otra persona destella un color único y tú la encuentras con la vista.',
              style: TextStyle(color: Colors.white38, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _PinLabel extends StatelessWidget {
  final bool isMe;
  final String label;
  const _PinLabel({required this.isMe, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = isMe ? kYou : kFriend;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: kBg.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 3),
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: c, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 10)],
          ),
        ),
      ],
    );
  }
}
