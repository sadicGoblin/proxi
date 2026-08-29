// Los mismos 5 estilos de mapa que la web; la elección se recuerda.
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Basemap {
  const Basemap(this.name, this.url, {this.subdomains = const [], this.maxZoom = 19});
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;
}

const basemaps = [
  Basemap('Callejero', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  Basemap('Satélite',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
  Basemap('Claro', 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c', 'd'], maxZoom: 20),
  Basemap('Oscuro', 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c', 'd'], maxZoom: 20),
  Basemap('Relieve',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Shaded_Relief/MapServer/tile/{z}/{y}/{x}',
      maxZoom: 13),
];

TileLayer tileLayerFor(Basemap b) => TileLayer(
      urlTemplate: b.url,
      subdomains: b.subdomains,
      maxNativeZoom: b.maxZoom,
      userAgentPackageName: 'cl.favric.proxi_nativa',
    );

Future<Basemap> loadBasemap() async {
  final p = await SharedPreferences.getInstance();
  final name = p.getString('proxi_basemap');
  return basemaps.firstWhere((b) => b.name == name, orElse: () => basemaps.first);
}

Future<void> saveBasemap(Basemap b) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('proxi_basemap', b.name);
}
