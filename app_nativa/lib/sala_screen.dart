// Sala en vivo: mapa con el grupo + MI posición compartida en tiempo real.
// La estrella de la app nativa: Geolocator con servicio en primer plano →
// la posición se sigue compartiendo con la pantalla bloqueada o la app atrás
// (Android muestra la notificación persistente "Proxi comparte tu ubicación").
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'core.dart';
import 'main.dart' show kBg, kSurface, kSurface2, kYou, kFriend, kFlag;

class SalaScreen extends StatefulWidget {
  const SalaScreen({super.key, required this.uid, required this.room});
  final String uid;
  final String room;

  @override
  State<SalaScreen> createState() => _SalaScreenState();
}

class _SalaScreenState extends State<SalaScreen> {
  final _mapCtl = MapController();
  StreamSubscription<Position>? _posSub;
  StreamSubscription? _membersSub;
  StreamSubscription? _juntaSub;

  Position? _me;
  bool _firstFix = true;
  bool _follow = false;
  String _status = 'Pidiendo permiso de ubicación…';
  bool _statusOk = false;

  String _name = '';
  final Map<String, Map<String, dynamic>> _members = {};
  Map<String, dynamic>? _junta;

  int _lastPush = 0;
  Timer? _pending;
  Timer? _uiTick;

  DocumentReference<Map<String, dynamic>> get _meDoc =>
      db.collection('salas').doc(widget.room).collection('miembros').doc(widget.uid);

  @override
  void initState() {
    super.initState();
    loadName().then((n) => _name = n);
    _startLocation();
    _listenRoom();
    // refresca "hace X min" y limpia desaparecidos aunque no lleguen snapshots
    _uiTick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  // ── ubicación con servicio en primer plano ────────────────────────────────
  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() { _status = 'Activa el GPS del teléfono'; _statusOk = false; });
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() { _status = 'Sin permiso de ubicación · actívalo en Ajustes'; _statusOk = false; });
      return;
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: Duration(seconds: 1),
      // Esto es lo que la web no puede hacer: el stream sobrevive al bloqueo
      // de pantalla gracias al servicio en primer plano con su notificación.
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Proxi comparte tu ubicación con el grupo',
        notificationText: 'Te ven llegar aunque bloquees la pantalla',
        notificationChannelName: 'Ubicación en vivo',
        enableWakeLock: true,
      ),
    );
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        _me = p;
        if (_firstFix) {
          _firstFix = false;
          _mapCtl.move(LatLng(p.latitude, p.longitude), 17);
        }
        if (_follow) _mapCtl.move(LatLng(p.latitude, p.longitude), _mapCtl.camera.zoom);
        setState(() { _status = 'Compartiendo en vivo · sigue con pantalla bloqueada'; _statusOk = true; });
        _push();
      },
      onError: (_) => setState(() { _status = 'Sin señal de GPS'; _statusOk = false; }),
    );
  }

  // Presencia con throttle (mismo contrato de datos y reglas que la web).
  Future<void> _push() async {
    final p = _me;
    if (p == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPush < 1200) {
      _pending ??= Timer(const Duration(milliseconds: 1300), () { _pending = null; _push(); });
      return;
    }
    _lastPush = now;
    try {
      await _meDoc.set({
        'name': _name,
        'photo': null,
        'lat': p.latitude,
        'lng': p.longitude,
        'acc': p.accuracy,
        'precise': false,
        'ts': FieldValue.serverTimestamp(),
        't': now,
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(now + 3600 * 1000),
      });
    } catch (_) {
      setState(() { _status = 'Sin conexión con la sala'; _statusOk = false; });
    }
  }

  // ── el grupo y la junta, en vivo ──────────────────────────────────────────
  void _listenRoom() {
    _membersSub = db
        .collection('salas').doc(widget.room).collection('miembros')
        .snapshots()
        .listen((snap) {
      _members.clear();
      for (final d in snap.docs) {
        final m = d.data();
        if (m['lat'] == null) continue;
        _members[d.id] = m;
      }
      setState(() {});
    });
    _juntaSub = db
        .collection('salas').doc(widget.room).collection('junta').doc('actual')
        .snapshots()
        .listen((snap) => setState(() => _junta = snap.data()));
  }

  @override
  void dispose() {
    _posSub?.cancel();          // esto además apaga el servicio en primer plano
    _membersSub?.cancel();
    _juntaSub?.cancel();
    _pending?.cancel();
    _uiTick?.cancel();
    _meDoc.delete().catchError((_) {});
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final markers = <Marker>[];

    _members.forEach((id, m) {
      final t = (m['t'] as num?)?.toInt() ?? now;
      final age = now - t;
      if (age > goneMs) return;
      final stale = age > staleMs;
      final isMe = id == widget.uid;
      final label = (isMe ? 'tú' : (m['name'] as String? ?? 'amigo')) +
          (stale ? ' · ${agoTxt(t)}' : '');
      markers.add(Marker(
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        width: 160, height: 56, alignment: Alignment.center,
        child: Opacity(
          opacity: stale ? .5 : 1,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _pill(label),
            const SizedBox(height: 3),
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: isMe ? kYou : kFriend,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: (isMe ? kYou : kFriend).withValues(alpha: .8), blurRadius: 12)],
              ),
            ),
          ]),
        ),
      ));
    });

    final j = _junta;
    final hasJunta = j != null && j['lat'] != null;
    if (hasJunta) {
      markers.add(Marker(
        point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        width: 170, height: 62, alignment: Alignment.topCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _pill((j['title'] as String?)?.isNotEmpty == true ? j['title'] as String : 'punto de junta',
              border: kFlag),
          const Text('🚩', style: TextStyle(fontSize: 26)),
        ]),
      ));
    }

    double? dist;
    if (hasJunta && _me != null) {
      dist = Geolocator.distanceBetween(_me!.latitude, _me!.longitude,
          (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
    }
    final vivos = _members.entries
        .where((e) => now - ((e.value['t'] as num?)?.toInt() ?? 0) <= staleMs).length;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtl,
          options: MapOptions(
            initialCenter: const LatLng(-33.4489, -70.6693),
            initialZoom: 4,
            maxZoom: 19,
            backgroundColor: kBg,
            onPositionChanged: (pos, byGesture) { if (byGesture && _follow) setState(() => _follow = false); },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'cl.favric.proxi_nativa',
            ),
            MarkerLayer(markers: markers),
          ],
        ),

        // barra superior
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              _pill('grupo · ${widget.room}', big: true),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'Volver al norte',
                onPressed: () => _mapCtl.rotate(0),
                icon: const Icon(Icons.explore_outlined),
              ),
            ]),
          ),
        ),

        // panel inferior
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            constraints: const BoxConstraints(maxWidth: 560),
            decoration: BoxDecoration(
              color: kSurface.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.circle, size: 9, color: _statusOk ? const Color(0xFF5FD08A) : kFlag),
                const SizedBox(width: 8),
                Expanded(child: Text(_status, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _chip('👥 ${vivos <= 1 ? "solo tú" : "$vivos en el grupo"}'),
                const SizedBox(width: 8),
                if (dist != null)
                  _chip(dist >= 1000
                      ? '🚩 ${(dist / 1000).toStringAsFixed(1)} km'
                      : '🚩 ${dist.round()} m al punto', color: kFlag),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() => _follow = !_follow);
                    final p = _me;
                    if (_follow && p != null) _mapCtl.move(LatLng(p.latitude, p.longitude), 17);
                  },
                  child: Text(_follow ? 'Siguiéndote' : 'Centrarme',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                          color: _follow ? kFriend : Colors.white)),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _pill(String txt, {bool big = false, Color? border}) => Container(
        padding: EdgeInsets.symmetric(horizontal: big ? 12 : 8, vertical: big ? 8 : 3),
        decoration: BoxDecoration(
          color: kBg.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border ?? Colors.white12),
        ),
        child: Text(txt,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: big ? 13 : 11, fontWeight: FontWeight.w700)),
      );

  Widget _chip(String txt, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: kSurface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: (color ?? Colors.white).withValues(alpha: .25)),
        ),
        child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}
