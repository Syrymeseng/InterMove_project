import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'app_config.dart';

class TransitStop {
  final int id;
  final String name;
  final LatLng point;
  final bool canBoard;
  final bool canExit;
  const TransitStop(this.id, this.name, this.point, this.canBoard, this.canExit);
}
class TransitLine {
  final String name;
  final String direction;
  final List<TransitStop> stops;
  const TransitLine(this.name, this.direction, this.stops);
}
class TransitOption {
  final TransitLine line;
  final int boarding;
  final int alighting;
  final double accessMeters;
  final double exitMeters;
  const TransitOption(this.line, this.boarding, this.alighting, this.accessMeters, this.exitMeters);
  TransitStop get first => line.stops[boarding];
  TransitStop get last => line.stops[alighting];
  List<LatLng> get schematic => line.stops.sublist(boarding, alighting + 1).map((s) => s.point).toList();
}

// PTv2 relations describe one direction. Never silently reverse them.
List<TransitLine> parseTransit(Map<String, dynamic> data) {
  final elements = data['elements'] as List? ?? [];
  final nodes = <int, dynamic>{for (final e in elements)
    if (e['type'] == 'node') e['id'] as int: e};
  final lines = <TransitLine>[];
  for (final relation in elements.where((e) => e['type'] == 'relation')) {
    final tags = relation['tags'] as Map? ?? {};
    // Legacy unordered relations are not safe for boarding/alighting planning.
    if (tags['public_transport:version'] != '2') continue;
    final members = relation['members'] as List? ?? [];
    var selected = members.where((m) => m['type'] == 'node' &&
      '${m['role']}'.startsWith('stop') && nodes.containsKey(m['ref'])).toList();
    if (selected.length < 2) {
      selected = members.where((m) => m['type'] == 'node' &&
        '${m['role']}'.startsWith('platform') && nodes.containsKey(m['ref'])).toList();
    }
    final stops = <TransitStop>[];
    for (final member in selected) {
      final node = nodes[member['ref']];
      final id = node['id'] as int;
      if (stops.isNotEmpty && stops.last.id == id) continue;
      final role = '${member['role']}';
      stops.add(TransitStop(id, (node['tags']?['name'] ?? 'Остановка $id').toString(),
        LatLng((node['lat'] as num).toDouble(), (node['lon'] as num).toDouble()),
        !role.endsWith('exit_only'), !role.endsWith('entry_only')));
    }
    if (stops.length >= 2) lines.add(TransitLine(
      (tags['ref'] ?? tags['name'] ?? 'Маршрут ${relation['id']}').toString(),
      (tags['to'] ?? tags['name'] ?? '').toString(), stops));
  }
  return lines;
}

// Direct rides only. Rank by straight-line walking distance, then ride stop count.
// These are candidate stops, not verified walkable access paths.
List<TransitOption> findTransitOptions(List<TransitLine> lines, LatLng a, LatLng b) {
  const distance = Distance();
  final options = <TransitOption>[];
  for (final line in lines) {
    TransitOption? best;
    double bestScore = double.infinity;
    for (var i = 0; i < line.stops.length - 1; i++) {
      if (!line.stops[i].canBoard) continue;
      final access = distance(a, line.stops[i].point);
      if (access > 1500) continue;
      for (var j = i + 1; j < line.stops.length; j++) {
        if (!line.stops[j].canExit) continue;
        final exit = distance(line.stops[j].point, b);
        if (exit > 1500) continue;
        final score = access + exit + (j - i) * 20;
        if (score < bestScore) {
          bestScore = score;
          best = TransitOption(line, i, j, access, exit);
        }
      }
    }
    if (best != null) options.add(best);
  }
  options.sort((a, b) => (a.accessMeters + a.exitMeters).compareTo(b.accessMeters + b.exitMeters));
  return options.take(6).toList();
}

class TransitService {
  final http.Client _client = http.Client();
  final Map<String, Future<List<TransitLine>>> _cache = {};
  Future<List<TransitLine>> nearby(LatLng a, bool rail) {
    final key = '${a.latitude.toStringAsFixed(2)}/${a.longitude.toStringAsFixed(2)}/$rail';
    return _cache.putIfAbsent(key, () async {
      try { return await _load(a, rail); }
      catch (_) { _cache.remove(key); rethrow; }
    });
  }
  Future<List<TransitLine>> _load(LatLng a, bool rail) async {
    if (_cache.length > 8) _cache.remove(_cache.keys.first);
    final types = rail ? 'tram|subway|light_rail' : 'bus|share_taxi|trolleybus';
    final query = '[out:json][timeout:25];'
      'relation["type"="route"]["route"~"^($types)\$"]'
      '["public_transport:version"="2"](around:2500,${a.latitude},${a.longitude})->.r;'
      '(.r;node(r.r););out body;';
    final response = await _client.post(Uri.parse(overpassUrl),
      headers: {'User-Agent': 'InterMoveStudentPrototype/0.3'},
      body: {'data': query}).timeout(const Duration(seconds: 35));
    if (response.statusCode != 200) throw const FormatException(
      'Источник остановок временно недоступен. Попробуй позже.');
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data.containsKey('remark')) throw const FormatException(
      'Источник не смог полностью загрузить маршруты. Попробуй позже.');
    return parseTransit(data);
  }
  void close() => _client.close();
}
