import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class Place {
  final String name;
  final LatLng point;
  const Place(this.name, this.point);
}

// Configure a 2GIS Geocoder API key in the application's settings.
// The key stays in memory and is never written into the source or database.
class AddressService {
  String apiKey = '';
  final http.Client _client = http.Client();
  bool get configured => apiKey.trim().isNotEmpty;

  Future<List<Place>> _request(Map<String, String> query) async {
    if (!configured) {
      throw const FormatException('Открой настройки и добавь ключ 2ГИС Geocoder API.');
    }
    final response = await _client.get(Uri.https(
      'catalog.api.2gis.com', '/3.0/items/geocode',
      {...query, 'fields': 'items.point', 'key': apiKey.trim()},
    )).timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException('Проверь ключ и доступ к Geocoder API.');
    }
    if (response.statusCode == 429) {
      throw const FormatException('Лимит запросов 2ГИС. Попробуй позже.');
    }
    if (response.statusCode != 200) {
      throw const FormatException('Сервис адресов временно недоступен.');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final code = (data['meta'] as Map?)?['code'];
    if (code == 404) return [];
    if (code != 200) {
      throw const FormatException('2ГИС отклонил запрос. Проверь ключ и его разрешения.');
    }
    final items = (data['result'] as Map?)?['items'] as List? ?? [];
    return items.where((item) => item['point'] != null).map((item) {
      final point = item['point'];
      return Place((item['full_name'] ?? item['address_name'] ?? item['name']).toString(),
        LatLng((point['lat'] as num).toDouble(), (point['lon'] as num).toDouble()));
    }).toList();
  }

  Future<List<Place>> search(String query) => _request({
    'q': query.trim(), 'location': '57.1670,50.2839',
  });

  Future<List<Place>> reverse(LatLng point) => _request({
    'lat': '${point.latitude}', 'lon': '${point.longitude}',
  });

  void close() => _client.close();
}
