import 'dart:async';
import 'package:flutter/material.dart';

class DemoDriver {
  final String name, gender, car;
  final int seats, eta;
  final bool wheelchair, pets, available;
  const DemoDriver(this.name, this.gender, this.car, this.seats, this.eta,
      {this.wheelchair = false, this.pets = false, this.available = true});
}

const demoDrivers = [
  DemoDriver('Алия', 'Женщина', 'Toyota Corolla · DEMO 01', 4, 4),
  DemoDriver('Дана', 'Женщина', 'Hyundai Staria · DEMO 02', 3, 7, wheelchair: true),
  DemoDriver('Айгерим', 'Женщина', 'Kia Rio · DEMO 03', 4, 6, pets: true),
  DemoDriver('Арман', 'Мужчина', 'Hyundai Accent · DEMO 04', 4, 3),
  DemoDriver('Данияр', 'Мужчина', 'Volkswagen Caddy · DEMO 05', 3, 8, wheelchair: true, pets: true),
  DemoDriver('Марат', 'Мужчина', 'Skoda Octavia · DEMO 06', 4, 5, pets: true, available: false),
];

List<DemoDriver> matchDemoDrivers({required String gender,
    required int passengers, required bool wheelchair, required bool pets}) {
  if (passengers < 1 || passengers > 4) return [];
  return demoDrivers.where((d) => d.available && d.seats >= passengers &&
    (gender == 'Без разницы' || d.gender == gender) &&
    (!wheelchair || d.wheelchair) && (!pets || d.pets)).toList()
    ..sort((a, b) => a.eta.compareTo(b.eta));
}

/// Visual simulation only: does not reserve a vehicle or create a booking.
class DemoDriverSearch extends StatefulWidget {
  final List<DemoDriver> candidates;
  final double fare;
  final Future<void> Function(DemoDriver)? onOrder;
  const DemoDriverSearch({super.key, required this.candidates, required this.fare,this.onOrder});
  @override
  State<DemoDriverSearch> createState() => _DemoDriverSearchState();
}

class _DemoDriverSearchState extends State<DemoDriverSearch> {
  Timer? timer;
  int tick = 0;
  bool sending=false, ordered=false;
  String? orderError;
  Future<void> order(DemoDriver driver) async {
    if(sending || ordered)return;
    setState((){sending=true;orderError=null;});
    try {await widget.onOrder!(driver);if(mounted)setState(()=>ordered=true);}
    catch(e){if(mounted)setState(()=>orderError=e is FormatException?e.message:"Не удалось сохранить. Повторите запрос.");}
    finally{if(mounted)setState(()=>sending=false);}
  }
  bool get done => tick >= 5;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => tick++);
      if (done) t.cancel();
    });
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final driver = widget.candidates.isEmpty ? null
        : widget.candidates[done ? 0 : tick % widget.candidates.length];
    return AlertDialog(
      title: Text(!done ? 'Ищем водителя…' : driver == null
          ? 'Подходящего водителя нет' : 'Водитель найден · демо'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child:
        Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Учебная симуляция. Реальная машина не приедет.'),
          const SizedBox(height: 20),
          if (!done) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          if (driver != null) ...[
            CircleAvatar(radius: 36, child: Text(driver.gender == 'Женщина' ? '👩' : '👨',
              style: const TextStyle(fontSize: 38))),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(driver.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            Text(driver.car, textAlign: TextAlign.center),
            Text(done ? 'Условное прибытие: ${driver.eta} мин' : 'Проверяем тестовые предложения'),
            if (driver.wheelchair) const Text('Перевозка в коляске: поддерживается'),
            if (driver.pets) const Text('С животными: можно'),
          ] else if (done)
            const Text('Измени число пассажиров или параметры поездки. '
              'Выбранные требования сохранены.'),
          const SizedBox(height: 16),
          Text('Расчёт: ${widget.fare.toStringAsFixed(2)} ₸'),
          Text(ordered?'ДЕМО-заказ сохранён в истории такси. Реальная машина не вызвана.':'Это симуляция: реальная бронь и оплата не выполняются.'),
          if(orderError!=null) Semantics(liveRegion:true,child:Text(orderError!)),
        ]))),
      actions: [
        if(done && driver!=null && widget.onOrder!=null) FilledButton(onPressed:sending || ordered?null:()=>order(driver),child:Text(ordered?'Сохранено':'Оформить ДЕМО-такси')),
        TextButton(onPressed: sending?null:() => Navigator.pop(context),
        child: Text(done ? 'Вернуться к маршруту' : 'Отменить поиск'))],
    );
  }
}
