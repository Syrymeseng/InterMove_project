import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'app_config.dart';

class Place {
  final String name;
  final LatLng point;
  final bool usableForReverse;
  const Place(this.name, this.point, {this.usableForReverse = false});
}

// Search only on explicit Enter/button. One request in flight, small memory cache.
class AddressService {
  final http.Client _client = http.Client();
  final Map<String, List<Place>> _cache = {};
  DateTime? _lastRequest;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Future<List<Place>> _request(String path, Map<String, String> query) {
    final task = _tail.then((_) => _perform(path, query));
    _tail = task.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return task;
  }
  Future<List<Place>> _perform(String path, Map<String, String> query) async {
    if (_closed) return [];
    final uri = Uri.parse('$photonBaseUrl$path').replace(queryParameters: query);
    if (_cache.containsKey('$uri')) return _cache['$uri']!;
    {
      if (_lastRequest != null) {
        final wait = 1100 - DateTime.now().difference(_lastRequest!).inMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      }
      if (_closed) return [];
      _lastRequest = DateTime.now();
      final response = await _client.get(uri, headers: {
        'User-Agent': 'InterMoveStudentPrototype/0.3',
      }).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) {
        throw const FormatException('Поиск временно недоступен. Попробуй позже или выбери точку на карте.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final places = parsePhoton(data);
      if (_cache.length >= 80) _cache.remove(_cache.keys.first);
      _cache['$uri'] = places;
      return places;
    }
  }
  Future<List<Place>> search(String q, {bool local = true}) => _request('/api/', {
    'q': q.trim(), 'lat': '50.2839', 'lon': '57.1670', 'limit': '6',
    if (local) 'bbox': '56.7,49.9,57.7,50.7',
  });
  Future<List<Place>> reverse(LatLng p) => _request('/reverse', {
    'lat': '${p.latitude}', 'lon': '${p.longitude}', 'limit': '5', 'radius': '0.05',
  });
  void close() { _closed = true; _client.close(); }
}

List<Place> parsePhoton(Map<String, dynamic> data) {
  final result = <Place>[];
  for (final feature in data['features'] as List? ?? []) {
    final geometry = feature['geometry'] as Map?;
    if (geometry?['type'] != 'Point') continue;
    final coords = geometry?['coordinates'] as List?;
    if (coords == null || coords.length < 2) continue;
    final props = feature['properties'] as Map? ?? {};
    final street = [props['street'], props['housenumber']]
        .where((v) => v != null && '$v'.isNotEmpty).join(' ');
    final labels = <String>{
      if (props['name'] != null) '${props['name']}',
      if (street.isNotEmpty) street,
      if (props['city'] != null) '${props['city']}',
      if (props['country'] != null) '${props['country']}',
    };
    result.add(Place(labels.isEmpty ? 'Точка на карте' : labels.join(', '),
      LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
      usableForReverse: street.isNotEmpty ||
        (props['name'] != null && const ['amenity', 'shop', 'building', 'tourism', 'leisure', 'highway']
          .contains(props['osm_key']))));
  }
  return result;
}

// Do not relabel an empty field with a distant town/region returned by a geocoder.
Place? nearbyAddress(List<Place> places, LatLng tapped) {
  final nearby = places.where((p) => p.usableForReverse &&
      const Distance()(p.point, tapped) <= 50).toList();
  nearby.sort((a, b) => const Distance()(a.point, tapped)
      .compareTo(const Distance()(b.point, tapped)));
  return nearby.isEmpty ? null : Place(nearby.first.name, tapped, usableForReverse: true);
}
