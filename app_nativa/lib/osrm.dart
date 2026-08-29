// Rutas por calles con OSRM (FOSSGIS sobre OpenStreetMap) — igual que la web.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OsrmResult {
  const OsrmResult(this.points, this.distM, this.durS);
  final List<LatLng> points;
  final double distM;
  final double durS;
}

const profileIcon = {'foot': '🚶', 'bike': '🚴', 'car': '🚗'};
const _profilePath = {'foot': 'routed-foot', 'bike': 'routed-bike', 'car': 'routed-car'};

Future<OsrmResult> osrmRoute(List<LatLng> pts, String profile) async {
  final path = _profilePath[profile] ?? 'routed-foot';
  final coords = pts.map((p) => '${p.longitude},${p.latitude}').join(';');
  final url = Uri.parse(
      'https://routing.openstreetmap.de/$path/route/v1/$profile/$coords?overview=full&geometries=geojson&alternatives=false&steps=false');
  final r = await http.get(url).timeout(const Duration(seconds: 12));
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['code'] != 'Ok' || j['routes'] == null || (j['routes'] as List).isEmpty) {
    throw Exception('osrm ${j['code']}');
  }
  final rt = (j['routes'] as List).first as Map<String, dynamic>;
  final coordsOut = ((rt['geometry'] as Map)['coordinates'] as List)
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();
  return OsrmResult(coordsOut, (rt['distance'] as num).toDouble(), (rt['duration'] as num).toDouble());
}

String fmtDist(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
String fmtDur(double s) {
  final min = (s / 60).round().clamp(1, 100000);
  if (min < 60) return '$min min';
  return '${min ~/ 60} h ${min % 60} min';
}
