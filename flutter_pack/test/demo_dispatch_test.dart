import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/demo_dispatch.dart';

void main() {
  test('Woman preference never returns a man or unavailable driver', () {
    final matches = matchDemoDrivers(gender: 'Женщина', passengers: 1,
      wheelchair: false, pets: false);
    expect(matches, isNotEmpty);
    expect(matches.every((d) => d.gender == 'Женщина' && d.available), isTrue);
  });
  test('Access and capacity stay mandatory, including no-match case', () {
    expect(matchDemoDrivers(gender: 'Без разницы', passengers: 4,
      wheelchair: true, pets: true), isEmpty);
    final match = matchDemoDrivers(gender: 'Без разницы', passengers: 3,
      wheelchair: true, pets: true).single;
    expect(match.name, 'Данияр');
  });
  testWidgets('Cancelling the simulation disposes its timer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DemoDriverSearch(
      candidates: demoDrivers, fare: 350)));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });
}
