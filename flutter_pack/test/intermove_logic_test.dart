import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/address_service.dart';
import '../lib/route_service.dart';
import '../lib/transit_service.dart';

void main() {
  test('Fare boundaries: each started 500 m costs 350 KZT', () {
    expect(fareForMeters(0), 0);
    expect(fareForMeters(1), 350);
    expect(fareForMeters(500), 350);
    expect(fareForMeters(500.1), 700);
    expect(fareForMeters(1000), 700);
    expect(fareForMeters(1001), 1050);
    expect(() => fareForMeters(-1), throwsArgumentError);
    expect(() => fareForMeters(double.nan), throwsArgumentError);
  });
  test('Walking and cycling use genuinely different graph profiles', () {
    expect(routeProfile(TravelMode.active, false), 'foot-walking');
    expect(routeProfile(TravelMode.active, true), 'cycling-regular');
    expect(routeProfile(TravelMode.taxi, true), 'driving-car');
  });
  test('Photon longitude/latitude order and empty results', () {
    final result = parsePhoton({'features': [{
      'geometry': {'type': 'Point', 'coordinates': [57.167, 50.2839]},
      'properties': {'name': 'Test', 'street': 'Street', 'housenumber': '5', 'city': 'Aktobe'}
    }]});
    expect(result.single.point.latitude, 50.2839);
    expect(result.single.point.longitude, 57.167);
    expect(result.single.name, contains('Street 5'));
    expect(parsePhoton({'features': []}), isEmpty);
  });
  test('Route summary uses road distance, not straight-line distance', () {
    final route = parseRoute({'features': [{
      'geometry': {'coordinates': [[57.1, 50.2], [57.2, 50.3]]},
      'properties': {'summary': {'distance': 1501.0, 'duration': 240.0}}
    }]}, 'driving-car');
    expect(route.meters, 1501);
    expect(route.fare, 1400);
    expect(route.points.first.latitude, 50.2);
    expect(() => parseRoute({'features': []}, 'driving-car'), throwsFormatException);
  });
  const a = TransitStop(1, 'A', LatLng(50, 57), true, true);
  const b = TransitStop(2, 'B', LatLng(50.05, 57), true, true);
  test('Transit respects stop direction and does not invent reverse trips', () {
    const line = TransitLine('10', 'B', [a, b]);
    expect(findTransitOptions([line], a.point, b.point).single.boarding, 0);
    expect(findTransitOptions([line], b.point, a.point), isEmpty);
  });
  test('Exit-only stop cannot be used to board', () {
    const noBoard = TransitStop(1, 'A', LatLng(50, 57), false, true);
    expect(findTransitOptions([const TransitLine('10', 'B', [noBoard, b])], a.point, b.point), isEmpty);
  });
  test('Unordered legacy relations are not treated as verified stop order', () {
    expect(parseTransit({'elements': [{'type': 'relation', 'id': 1,
      'tags': {'route': 'bus'}, 'members': []}]}), isEmpty);
  });
}
