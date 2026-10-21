import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'app_config.dart';

enum TravelMode { taxi, bus, rail, intercity, delivery, active }
String modeLabel(TravelMode mode) => switch (mode) {
  TravelMode.taxi => 'Обычное такси', TravelMode.bus => 'Автобусы',
  TravelMode.rail => 'Трамвай / метро', TravelMode.intercity => 'Межгород',
  TravelMode.delivery => 'Доставка', TravelMode.active => 'Пешком / велосипед',
};
String routeProfile(TravelMode mode, bool cycling) => mode == TravelMode.active
    ? (cycling ? 'cycling-regular' : 'foot-walking') : 'driving-car';
bool isTransit(TravelMode mode) => mode == TravelMode.bus || mode == TravelMode.rail;
double fareForMeters(double meters) {
  if (!meters.isFinite || meters < 0) throw ArgumentError('Invalid distance');
  return (meters * 70).round() / 100;
}

class RoadRoute {
  final List<LatLng> points;
  final double meters;
  final double seconds;
  final String profile;
  const RoadRoute(this.points, this.meters, this.seconds, this.profile);
  double get fare => fareForMeters(meters);
}

RoadRoute parseRoute(Map<String, dynamic> data, String profile) {
  final features = data['features'] as List? ?? [];
  if (features.isEmpty) throw const FormatException('Маршрут не найден.');
  final feature = features.first;
  final summary = feature['properties']['summary'];
  final points = (feature['geometry']['coordinates'] as List).map((p) =>
    LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
  if (points.length < 2) throw const FormatException('Маршрут не найден.');
  return RoadRoute(points, (summary['distance'] as num).toDouble(),
    (summary['duration'] as num).toDouble(), profile);
}

class RouteService {
  String apiKey = routingApiKey;
  final http.Client _client = http.Client();
  final Map<String, RoadRoute> _cache = {};
  bool get configured => apiKey.trim().isNotEmpty;
  Future<RoadRoute> route(LatLng a, LatLng b, String profile) async {
    if (!configured) throw const FormatException(
      'Маршрут требует ключ openrouteservice. Поле пока пустое: добавишь его в настройках позже.');
    if (const Distance()(a, b) < 2) {
      throw const FormatException('Точки слишком близко. Выбери другое место.');
    }
    final id = '$profile/${a.latitude},${a.longitude}/${b.latitude},${b.longitude}';
    if (_cache.containsKey(id)) return _cache[id]!;
    final response = await _client.post(Uri.parse('$routingBaseUrl/directions/$profile/geojson'),
      headers: {'Authorization': apiKey.trim(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'coordinates': [[a.longitude, a.latitude], [b.longitude, b.latitude]],
        'preference': 'shortest', 'instructions': false,
      })).timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException('Проверь ключ маршрутов и доступ к Directions API.');
    }
    if (response.statusCode == 429) {
      throw const FormatException('Лимит сервиса маршрутов. Повтори позже.');
    }
    if (response.statusCode == 404 || response.statusCode == 400) {
      throw const FormatException('Нет подходящего маршрута. Попробуй поставить точки ближе к дороге или тропе.');
    }
    if (response.statusCode != 200) throw const FormatException('Сервис маршрутов временно недоступен.');
    final result = parseRoute(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>, profile);
    if (_cache.length >= 30) _cache.remove(_cache.keys.first);
    _cache[id] = result;
    return result;
  }
  void close() => _client.close();
}
