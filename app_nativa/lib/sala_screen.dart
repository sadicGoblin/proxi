// Sala en vivo con paridad de la web (junta.html): junta con roles, hora,
// historial, rutas OSRM, estilos de mapa, punto exacto manual e invitación.
// Y lo que la web no puede: la posición se sigue compartiendo con la pantalla
// bloqueada (servicio en primer plano de Geolocator).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import 'basemaps.dart';
import 'core.dart';
import 'main.dart' show kBg, kSurface, kSurface2, kYou, kFriend, kFlag, kMute;
import 'osrm.dart';

const _juntaTtlMs = 30 * 24 * 3600 * 1000; // la junta expira sola al mes
const _liberarMs = 24 * 3600 * 1000;       // sin ediciones en 24 h → se libera

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
  StreamSubscription? _rutaSub;

  Position? _gps;
  LatLng? _manual;              // punto exacto fijado a mano (±1,5 m)
  bool _usingManual = false;
  bool _firstFix = true;
  bool _follow = false;
  String _status = 'Pidiendo permiso de ubicación…';
  bool _statusOk = false;

  String _name = '';
  final Map<String, Map<String, dynamic>> _members = {};
  Map<String, dynamic>? _junta;
  bool _firstJunta = true;
  bool _placing = false;
  int _lastAsk = 0;

  Basemap _base = basemaps.first;

  // ruta a pie hasta la junta
  bool _routeOn = false;
  List<LatLng> _routePts = [];
  String _routeChip = '';
  LatLng? _routeFrom, _routeTo;
  int _routeAt = 0;
  bool _routeBusy = false;

  // ruta del grupo (dibujada desde la web)
  Map<String, dynamic>? _ruta;
  List<LatLng> _rutaPts = [];
  String _rutaChip = '';
  String _rutaKey = '';

  int _lastPush = 0;
  Timer? _pending;
  Timer? _tick;

  DocumentReference<Map<String, dynamic>> get _meDoc =>
      db.collection('salas').doc(widget.room).collection('miembros').doc(widget.uid);
  DocumentReference<Map<String, dynamic>> get _juntaDoc =>
      db.collection('salas').doc(widget.room).collection('junta').doc('actual');
  CollectionReference<Map<String, dynamic>> get _cambios => _juntaDoc.collection('cambios');
  DocumentReference<Map<String, dynamic>> get _rutaDoc =>
      db.collection('salas').doc(widget.room).collection('ruta').doc('actual');

  ({double lat, double lng, double acc, bool precise})? _myPos() {
    if (_usingManual && _manual != null) {
      return (lat: _manual!.latitude, lng: _manual!.longitude, acc: 1.5, precise: true);
    }
    final p = _gps;
    if (p == null) return null;
    return (lat: p.latitude, lng: p.longitude, acc: p.accuracy, precise: false);
  }

  @override
  void initState() {
    super.initState();
    loadName().then((n) => _name = n);
    loadBasemap().then((b) => setState(() => _base = b));
    _startLocation();
    _listenRoom();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateRoute(false);
      if (DateTime.now().second < 5) setState(() {}); // refresca "hace X min"
    });
  }

  // ── ubicación (servicio en primer plano: sigue con pantalla bloqueada) ────
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
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Proxi comparte tu ubicación con el grupo',
        notificationText: 'Te ven llegar aunque bloquees la pantalla',
        notificationChannelName: 'Ubicación en vivo',
        enableWakeLock: true,
      ),
    );
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        _gps = p;
        if (_firstFix) {
          _firstFix = false;
          if (_junta?['lat'] == null) _mapCtl.move(LatLng(p.latitude, p.longitude), 17);
        }
        if (_follow && !_usingManual) _mapCtl.move(LatLng(p.latitude, p.longitude), _mapCtl.camera.zoom);
        setState(() { _status = 'Compartiendo en vivo · sigue con pantalla bloqueada'; _statusOk = true; });
        _push();
      },
      onError: (_) => setState(() { _status = 'Sin señal de GPS'; _statusOk = false; }),
    );
  }

  Future<void> _push() async {
    final p = _myPos();
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
        'photo': profilePhoto(),
        'lat': p.lat, 'lng': p.lng, 'acc': p.acc, 'precise': p.precise,
        'ts': FieldValue.serverTimestamp(), 't': now,
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(now + 3600 * 1000),
      });
    } catch (_) {
      setState(() { _status = 'Sin conexión con la sala'; _statusOk = false; });
    }
  }

  // ── streams de la sala ────────────────────────────────────────────────────
  void _listenRoom() {
    _membersSub = db.collection('salas').doc(widget.room).collection('miembros')
        .snapshots().listen((snap) {
      _members.clear();
      for (final d in snap.docs) {
        final m = d.data();
        if (m['lat'] == null) continue;
        _members[d.id] = m;
      }
      setState(() {});
    });

    _juntaSub = _juntaDoc.snapshots().listen((snap) {
      final prev = _junta;
      _junta = snap.data();
      final j = _junta;
      if (j != null && j['lat'] != null && _firstJunta) {
        _mapCtl.move(LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()), 17);
      }
      // aviso si lo cambió otra persona
      if (!_firstJunta && j != null && prev != null &&
          j['byUid'] != widget.uid && j['t'] != prev['t'] && mounted) {
        final moved = prev['lat'] != j['lat'] || prev['lng'] != j['lng'];
        final retimed = prev['when'] != j['when'];
        final what = moved && retimed ? 'cambió el lugar y la hora'
            : moved ? 'movió el punto de junta 🚩'
            : retimed ? 'cambió la hora 🕒' : 'cambió los permisos 🔑';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${j['by'] ?? 'Alguien'} $what'
              '${j['when'] != null ? ' · ${_fmtWhen((j['when'] as num).toInt())}' : ''}'),
        ));
        if (moved) {
          _mapCtl.move(LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
              _mapCtl.camera.zoom < 16 ? 16 : _mapCtl.camera.zoom);
        }
      }
      _firstJunta = false;
      setState(() {});
      _updateRoute(true);
    });

    _rutaSub = _rutaDoc.snapshots().listen((snap) {
      _ruta = snap.data();
      _renderRuta();
    });
  }

  // ── gobernanza de la junta (idéntica a la web / firestore.rules) ──────────
  bool _allowedByPolicy(Map<String, dynamic>? j) {
    if (j == null || j['ownerUid'] == null) return true;
    if (j['ownerUid'] == widget.uid) return true;
    if (j['policy'] == 'all') return true;
    if (j['policy'] == 'editors' && (j['editors'] as List? ?? []).contains(widget.uid)) return true;
    return false;
  }

  bool _staleJunta(Map<String, dynamic>? j) {
    final t = (j?['t'] as num?)?.toInt();
    return t != null && DateTime.now().millisecondsSinceEpoch - t > _liberarMs;
  }

  bool _canEdit() => _allowedByPolicy(_junta) || _staleJunta(_junta);
  bool get _isOwner => _junta != null && _junta!['ownerUid'] == widget.uid;

  String _ownerName() {
    final o = _junta?['ownerUid'];
    if (o == null) return 'el organizador';
    if (o == widget.uid) return 'tú';
    return _members[o]?['name'] as String? ?? 'el organizador';
  }

  Future<void> _saveJunta(Map<String, dynamic> patch, String what) async {
    final base = _junta ?? {};
    final now = DateTime.now().millisecondsSinceEpoch;
    final takeover = base['ownerUid'] == null ||
        (base['ownerUid'] != widget.uid && !_allowedByPolicy(base) && _staleJunta(base));
    final reclamo = takeover && base['ownerUid'] != null && base['ownerUid'] != widget.uid;
    final data = {
      'lat': patch['lat'] ?? base['lat'],
      'lng': patch['lng'] ?? base['lng'],
      'when': patch.containsKey('when') ? patch['when'] : base['when'],
      'title': patch.containsKey('title') ? patch['title'] : (base['title'] ?? ''),
      'ownerUid': takeover ? widget.uid : base['ownerUid'],
      'policy': patch.containsKey('policy') ? patch['policy'] : (takeover ? 'owner' : (base['policy'] ?? 'owner')),
      'editors': patch.containsKey('editors') ? patch['editors'] : (takeover ? [] : (base['editors'] ?? [])),
      'by': _name, 'byUid': widget.uid, 't': now, 'ts': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromMillisecondsSinceEpoch(now + _juntaTtlMs),
    };
    try {
      await _juntaDoc.set(data);
      await _cambios.add({
        'by': _name,
        'what': what + (reclamo ? ' · reclamó la junta (organizador inactivo) 👑' : ''),
        't': now, 'ts': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(now + _juntaTtlMs),
      });
    } catch (_) {
      _snack(_allowedByPolicy(_junta)
          ? 'No se pudo guardar (revisa conexión)'
          : 'Solo ${_ownerName()} puede cambiar la junta 🔒');
    }
  }

  Future<void> _pedirMover() async {
    _snack('🔒 Solo ${_ownerName()} puede mover la junta · le avisamos que quieres moverla 🙋');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAsk < 60000) return;
    _lastAsk = now;
    try {
      await _cambios.add({
        'by': _name, 'what': 'quiere mover la junta 🙋',
        't': now, 'ts': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromMillisecondsSinceEpoch(now + _juntaTtlMs),
      });
    } catch (_) {}
  }

  // ── rutas ─────────────────────────────────────────────────────────────────
  Future<void> _updateRoute(bool force) async {
    if (!_routeOn || _routeBusy) return;
    final p = _myPos();
    final j = _junta;
    if (p == null || j == null || j['lat'] == null) {
      if (_routePts.isNotEmpty) setState(() { _routePts = []; _routeChip = ''; });
      return;
    }
    final from = LatLng(p.lat, p.lng);
    final to = LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
    final moved = _routeFrom == null || _routeTo == null ||
        Geolocator.distanceBetween(from.latitude, from.longitude, _routeFrom!.latitude, _routeFrom!.longitude) > 25 ||
        Geolocator.distanceBetween(to.latitude, to.longitude, _routeTo!.latitude, _routeTo!.longitude) > 1;
    if (!moved && _routePts.isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _routeAt < 10000) return;
    _routeBusy = true; _routeAt = now;
    _routeFrom = from; _routeTo = to;
    try {
      final r = await osrmRoute([from, to], 'foot');
      if (mounted) setState(() { _routePts = r.points; _routeChip = '🥾 ${fmtDist(r.distM)} · ${fmtDur(r.durS)} a pie'; });
    } catch (_) {
      if (mounted) setState(() { _routePts = [from, to]; _routeChip = '🧭 línea recta · sin servicio de rutas'; });
    } finally {
      _routeBusy = false;
    }
  }

  Future<void> _renderRuta() async {
    final r = _ruta;
    final raw = (r?['pts'] as List? ?? [])
        .where((p) => p is Map && p['lat'] is num && p['lng'] is num)
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .take(30).toList();
    if (raw.length < 2) {
      if (_rutaPts.isNotEmpty || _rutaChip.isNotEmpty) setState(() { _rutaPts = []; _rutaChip = ''; _rutaKey = ''; });
      return;
    }
    final prof = profileIcon.containsKey(r?['profile']) ? r!['profile'] as String : 'foot';
    final key = '$prof|${raw.map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}').join(';')}';
    if (key == _rutaKey) return;
    _rutaKey = key;
    final who = (r?['by'] as String?)?.isNotEmpty == true ? ' · de ${r!['by']}' : '';
    try {
      final res = await osrmRoute(raw, prof);
      if (_rutaKey != key || !mounted) return;
      setState(() { _rutaPts = res.points; _rutaChip = '${profileIcon[prof]} ${fmtDist(res.distM)} · ${fmtDur(res.durS)}$who'; });
    } catch (_) {
      if (_rutaKey != key || !mounted) return;
      setState(() { _rutaPts = raw; _rutaChip = '${profileIcon[prof]} línea directa$who'; });
    }
  }

  @override
  void dispose() {
    _posSub?.cancel(); // apaga también el servicio en primer plano
    _membersSub?.cancel();
    _juntaSub?.cancel();
    _rutaSub?.cancel();
    _pending?.cancel();
    _tick?.cancel();
    _meDoc.delete().catchError((_) {});
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── acciones ──────────────────────────────────────────────────────────────
  void _onLongPress(LatLng ll) {
    if (_placing) return;
    showModalBottomSheet(context: context, backgroundColor: kSurface, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Text('🚩', style: TextStyle(fontSize: 22)),
          title: Text(_junta?['lat'] == null ? 'Fijar la junta aquí' : 'Mover la junta aquí',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            Navigator.pop(ctx);
            if (!_canEdit()) { _pedirMover(); return; }
            final isNew = _junta?['lat'] == null;
            await _saveJunta({'lat': ll.latitude, 'lng': ll.longitude},
                isNew ? 'fijó el punto de junta 🚩' : 'movió el punto de junta 📍');
            if (isNew && _junta?['when'] == null) _openHora();
          },
        ),
        ListTile(
          leading: const Text('📍', style: TextStyle(fontSize: 22)),
          title: const Text('Fijar MI punto exacto aquí (±1,5 m)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Tu GPS deja de mandar hasta que vuelvas a él',
              style: TextStyle(color: kMute, fontSize: 12)),
          onTap: () {
            Navigator.pop(ctx);
            setState(() { _manual = ll; _usingManual = true; });
            _push();
            _snack('Tu punto exacto quedó fijado ✓ · el grupo ya lo ve');
          },
        ),
      ]),
    ));
  }

  Future<void> _confirmPlace() async {
    final c = _mapCtl.camera.center;
    final isNew = _junta?['lat'] == null;
    setState(() => _placing = false);
    await _saveJunta({'lat': c.latitude, 'lng': c.longitude},
        isNew ? 'fijó el punto de junta 🚩' : 'movió el punto de junta 📍');
    if (isNew && _junta?['when'] == null) _openHora();
  }

  Future<void> _openHora() async {
    if (!_canEdit()) { _pedirMover(); return; }
    final base = _junta?['when'] != null
        ? DateTime.fromMillisecondsSinceEpoch((_junta!['when'] as num).toInt())
        : DateTime.now().add(const Duration(hours: 1));
    final titleCtl = TextEditingController(text: _junta?['title'] as String? ?? '');
    final d = await showDatePicker(context: context, initialDate: base,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (t == null || !mounted) return;
    final when = DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch;
    final title = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Nombre del lugar (opcional)', style: TextStyle(fontSize: 16)),
      content: TextField(controller: titleCtl, maxLength: 40,
          decoration: const InputDecoration(hintText: 'ej: entrada del parque')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, titleCtl.text.trim()), child: const Text('Guardar')),
      ],
    ));
    final hadWhen = _junta?['when'] != null;
    await _saveJunta({'when': when, 'title': (title ?? titleCtl.text).trim()},
        hadWhen ? 'cambió la hora a las ${_fmtWhen(when)} 🕒' : 'puso hora: ${_fmtWhen(when)} 🕒');
  }

  Future<void> _openPerm() async {
    var pol = _junta?['policy'] as String? ?? 'owner';
    final editors = List<String>.from(_junta?['editors'] as List? ?? []);
    await showModalBottomSheet(context: context, backgroundColor: kSurface, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('¿Quién puede mover la junta?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Text('Todo cambio queda en el historial.', style: TextStyle(color: kMute, fontSize: 12)),
            const SizedBox(height: 6),
            for (final opt in [('owner', '🔒 Solo yo'), ('editors', '🔑 Yo + quienes marque'), ('all', '🔓 Todos en el grupo')])
              RadioListTile<String>(value: opt.$1, groupValue: pol, dense: true,
                  title: Text(opt.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  onChanged: (v) => setS(() => pol = v!)),
            if (pol == 'editors')
              ..._members.entries.where((e) => e.key != widget.uid).map((e) => CheckboxListTile(
                    dense: true, value: editors.contains(e.key),
                    title: Text(e.value['name'] as String? ?? 'amigo'),
                    onChanged: (v) => setS(() => v == true ? editors.add(e.key) : editors.remove(e.key)),
                  )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kFlag, foregroundColor: const Color(0xFF3A2C00)),
              onPressed: () async {
                Navigator.pop(ctx);
                final msg = pol == 'all' ? 'dejó que todos muevan la junta 🔓'
                    : pol == 'editors' ? 'eligió ${editors.length} persona(s) con permiso 🔑'
                    : 'restringió la junta: solo el organizador 🔒';
                await _saveJunta({'policy': pol, 'editors': pol == 'editors' ? editors : <String>[]}, msg);
              },
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      )));
  }

  void _openHist() {
    showModalBottomSheet(context: context, backgroundColor: kSurface, builder: (ctx) => SafeArea(
      child: SizedBox(height: 320, child: Column(children: [
        const Padding(padding: EdgeInsets.all(14),
            child: Text('CAMBIOS DE LA JUNTA', style: TextStyle(color: kMute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _cambios.orderBy('t', descending: true).limit(8).snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text('Sin cambios aún', style: TextStyle(color: kMute)));
            return ListView(children: [
              for (final d in docs)
                ListTile(dense: true,
                    title: Text('${d.data()['by'] ?? 'Alguien'} ${d.data()['what'] ?? ''}',
                        style: const TextStyle(fontSize: 13)),
                    trailing: Text(agoTxt((d.data()['t'] as num?)?.toInt() ?? 0),
                        style: const TextStyle(color: kMute, fontSize: 11))),
            ]);
          },
        )),
      ])),
    ));
  }

  void _openPeople() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final j = _junta;
    final rows = _members.entries.toList()
      ..sort((a, b) {
        if (a.key == widget.uid) return -1;
        if (b.key == widget.uid) return 1;
        return (a.value['name'] as String? ?? 'zz').toLowerCase()
            .compareTo((b.value['name'] as String? ?? 'zz').toLowerCase());
      });
    showModalBottomSheet(context: context, backgroundColor: kSurface, builder: (ctx) => SafeArea(
      child: SizedBox(height: 330, child: ListView(padding: const EdgeInsets.only(top: 10), children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('QUIÉNES ESTÁN · distancia al punto', style: TextStyle(color: kMute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
        for (final e in rows)
          Builder(builder: (_) {
            final m = e.value;
            final t = (m['t'] as num?)?.toInt() ?? now;
            final stale = now - t > staleMs;
            final photo = (m['photo'] is String && (m['photo'] as String).startsWith('https://')) ? m['photo'] as String : null;
            String sub = stale ? agoTxt(t) : 'en vivo';
            if (j?['lat'] != null && m['lat'] != null) {
              final d = Geolocator.distanceBetween((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble(),
                  (j!['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
              sub = '${fmtDist(d)} al punto · $sub';
            }
            return ListTile(dense: true,
              leading: CircleAvatar(radius: 15, backgroundColor: kSurface2,
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null ? Text(((m['name'] as String?) ?? '?').isNotEmpty ? (m['name'] as String)[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 12)) : null),
              title: Text('${e.key == widget.uid ? 'Tú' : (m['name'] ?? 'amigo')}'
                  '${j?['ownerUid'] == e.key ? ' 👑' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              trailing: Text(sub, style: const TextStyle(color: kMute, fontSize: 11.5)),
            );
          }),
      ])),
    ));
  }

  void _pickBase() {
    showModalBottomSheet(context: context, backgroundColor: kSurface, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final b in basemaps)
          ListTile(dense: true,
            title: Text(b.name, style: TextStyle(fontWeight: FontWeight.w700,
                color: b.name == _base.name ? kFlag : Colors.white)),
            trailing: b.name == _base.name ? const Icon(Icons.check, color: kFlag, size: 18) : null,
            onTap: () { Navigator.pop(ctx); setState(() => _base = b); saveBasemap(b); }),
      ]),
    ));
  }

  void _share() {
    final when = _junta?['when'] != null ? ' ${_fmtWhen((_junta!['when'] as num).toInt())}' : '';
    SharePlus.instance.share(ShareParams(
        text: 'Junta del grupo$when 🚩 mira el punto exacto en el mapa (si cambia, lo ves al tiro): '
            'https://proxi-live.web.app/junta.html?s=${widget.room}'));
  }

  // ── formato ───────────────────────────────────────────────────────────────
  String _fmtWhen(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    if (same(d, now)) return 'hoy $hm';
    if (same(d, now.add(const Duration(days: 1)))) return 'mañana $hm';
    const wd = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    const mo = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]} $hm';
  }

  String _durTxt(int ms) {
    final m = (ms / 60000).round();
    if (m < 60) return '$m min';
    return '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60} min' : ''}';
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
      final crown = _junta?['ownerUid'] == id ? '👑 ' : '';
      final label = crown + (isMe ? 'tú' : (m['name'] as String? ?? 'amigo')) + (stale ? ' · ${agoTxt(t)}' : '');
      final photo = (m['photo'] is String && (m['photo'] as String).startsWith('https://')) ? m['photo'] as String : null;
      final color = isMe ? kYou : kFriend;
      markers.add(Marker(
        point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        width: 170, height: photo != null ? 66 : 56, alignment: Alignment.center,
        child: Opacity(opacity: stale ? .5 : 1, child: Column(mainAxisSize: MainAxisSize.min, children: [
          _pill(label),
          const SizedBox(height: 3),
          photo != null
              ? Container(width: 32, height: 32, decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                  image: DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: .7), blurRadius: 10)]))
              : Container(width: 18, height: 18, decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: .8), blurRadius: 12)])),
        ])),
      ));
    });

    final j = _junta;
    final hasJunta = j != null && j['lat'] != null;
    if (hasJunta) {
      markers.add(Marker(
        point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        width: 180, height: 64, alignment: Alignment.topCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _pill((j['title'] as String?)?.isNotEmpty == true ? j['title'] as String : 'punto de junta', border: kFlag),
          const Text('🚩', style: TextStyle(fontSize: 26)),
        ]),
      ));
    }

    double? dist;
    final me = _myPos();
    if (hasJunta && me != null) {
      dist = Geolocator.distanceBetween(me.lat, me.lng, (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
    }
    final vivos = _members.entries.where((e) => now - ((e.value['t'] as num?)?.toInt() ?? 0) <= staleMs).length;
    final editable = _canEdit();

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtl,
          options: MapOptions(
            initialCenter: const LatLng(-33.4489, -70.6693),
            initialZoom: 4, maxZoom: 20, backgroundColor: kBg,
            onLongPress: (_, ll) => _onLongPress(ll),
            onPositionChanged: (pos, byGesture) { if (byGesture && _follow) setState(() => _follow = false); },
          ),
          children: [
            tileLayerFor(_base),
            if (_rutaPts.length > 1)
              PolylineLayer(polylines: [Polyline(points: _rutaPts, strokeWidth: 5, color: const Color(0xE6A78BFA))]),
            if (_routeOn && _routePts.length > 1)
              PolylineLayer(polylines: [Polyline(points: _routePts, strokeWidth: 4, color: const Color(0xD945C6F0))]),
            MarkerLayer(markers: markers),
          ],
        ),

        // mira central en modo "colocar la junta"
        if (_placing) IgnorePointer(child: Center(
          child: Icon(Icons.add_location_alt_outlined, size: 52, color: kFlag,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]),
        )),

        // barra superior
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            IconButton.filledTonal(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: 8),
            _pill('grupo · ${widget.room}', big: true),
            const Spacer(),
            IconButton.filledTonal(tooltip: 'Estilo de mapa', onPressed: _pickBase, icon: const Icon(Icons.layers_outlined)),
            IconButton.filledTonal(tooltip: 'Volver al norte', onPressed: () => _mapCtl.rotate(0), icon: const Icon(Icons.explore_outlined)),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: kYou),
              tooltip: 'Invitar al grupo', onPressed: _share, icon: const Icon(Icons.share)),
          ]),
        )),

        // barra de confirmación al colocar la junta
        if (_placing) Align(alignment: Alignment.bottomCenter, child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: kSurface.withValues(alpha: .95), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => setState(() => _placing = false), child: const Text('Cancelar', style: TextStyle(color: Colors.white))),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kFlag, foregroundColor: const Color(0xFF3A2C00)),
                onPressed: _confirmPlace,
                child: const Text('🚩 La junta es aquí', style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
        )),

        // panel inferior
        if (!_placing) Align(alignment: Alignment.bottomCenter, child: SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                Expanded(child: Text(_status, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                if (dist != null) Text(fmtDist(dist), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              const SizedBox(height: 9),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                if (hasJunta) _chip(j['when'] != null ? '🕒 ${_fmtWhen((j['when'] as num).toInt())}' : '🕒 sin hora aún', color: kFlag, onTap: _openHora),
                if (hasJunta && j['when'] != null) ...[
                  const SizedBox(width: 6),
                  _chip((j['when'] as num).toInt() > now
                      ? 'falta ${_durTxt((j['when'] as num).toInt() - now)}'
                      : 'empezó hace ${_durTxt(now - (j['when'] as num).toInt())}'),
                ],
                const SizedBox(width: 6),
                _chip('👥 ${vivos <= 1 ? 'solo tú' : '$vivos en el grupo'}', onTap: _openPeople),
                if (hasJunta) ...[
                  const SizedBox(width: 6),
                  _chip(_isOwner ? '🔒 tú decides quién mueve' : (j['policy'] == 'all' ? '🔓 todos pueden' : '🔒 la mueve ${_ownerName()}'),
                      onTap: _isOwner ? _openPerm : null),
                ],
                if (_routeChip.isNotEmpty) ...[const SizedBox(width: 6), _chip(_routeChip, color: kFriend)],
                if (_rutaChip.isNotEmpty) ...[const SizedBox(width: 6), _chip(_rutaChip, color: const Color(0xFFA78BFA))],
                if (_usingManual) ...[const SizedBox(width: 6),
                  _chip('volver a GPS', color: kFriend, onTap: () { setState(() { _usingManual = false; _manual = null; }); _push(); })],
              ])),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: FilledButton.tonal(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0x26FFD166)),
                  onPressed: () {
                    if (!_canEdit()) { _pedirMover(); return; }
                    setState(() => _placing = true);
                    final target = hasJunta
                        ? LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble())
                        : (me != null ? LatLng(me.lat, me.lng) : null);
                    if (target != null) _mapCtl.move(target, _mapCtl.camera.zoom < 17 ? 17 : _mapCtl.camera.zoom);
                  },
                  child: Text(hasJunta ? (editable ? '📍 Mover la junta' : '🔒 Pedir mover') : '🚩 Fijar la junta',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFFFE4A1))),
                )),
                const SizedBox(width: 7),
                IconButton.filledTonal(tooltip: 'Ruta a pie a la junta',
                    style: IconButton.styleFrom(backgroundColor: _routeOn ? const Color(0x3345C6F0) : null),
                    onPressed: () { setState(() { _routeOn = !_routeOn; if (!_routeOn) { _routePts = []; _routeChip = ''; _routeFrom = null; } }); _updateRoute(true); },
                    icon: const Icon(Icons.route_outlined, size: 20)),
                IconButton.filledTonal(tooltip: 'Historial', onPressed: _openHist, icon: const Icon(Icons.history, size: 20)),
                IconButton.filledTonal(tooltip: _follow ? 'Siguiéndote' : 'Centrarme',
                    style: IconButton.styleFrom(backgroundColor: _follow ? const Color(0x3345C6F0) : null),
                    onPressed: () {
                      setState(() => _follow = !_follow);
                      final p = _myPos();
                      if (_follow && p != null) _mapCtl.move(LatLng(p.lat, p.lng), 17);
                    },
                    icon: const Icon(Icons.my_location, size: 20)),
              ]),
            ]),
          ),
        )),
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
        child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: big ? 13 : 11, fontWeight: FontWeight.w700)),
      );

  Widget _chip(String txt, {Color? color, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kSurface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: (color ?? Colors.white).withValues(alpha: .28)),
          ),
          child: Text(txt, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ),
      );
}
