import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'address_service.dart';
import 'local_store.dart';
import 'profile_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalStore? store;
  try { store = await LocalStore.open(); } catch (_) { /* Guest map still opens. */ }
  runApp(InterMoveApp(store: store));
}

class InterMoveApp extends StatelessWidget {
  final LocalStore? store;
  const InterMoveApp({super.key, this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'InterMove', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246BFD)),
      inputDecorationTheme: InputDecorationTheme(filled: true,
        fillColor: const Color(0xFFF4F6FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
    ),
    home: HomeScreen(store: store),
  );
}

class HomeScreen extends StatefulWidget {
  final LocalStore? store;
  const HomeScreen({super.key, required this.store});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const aktobe = LatLng(50.2839, 57.1670);
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final mapController = MapController();
  final addresses = AddressService();
  final fromText = TextEditingController();
  final toText = TextEditingController();
  Account? account;
  Place? from;
  Place? to;
  List<Place> results = [];
  String transport = 'Такси';
  String? status;
  bool selectingFrom = false;
  bool busy = false;
  bool panelVisible = true;
  int generation = 0;

  @override
  void dispose() {
    addresses.close(); mapController.dispose(); fromText.dispose(); toText.dispose();
    super.dispose();
  }

  String coordinates(LatLng p) => '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  void invalidate() {
    generation++;
    busy = false;
    results = [];
    status = null;
  }

  void chooseTarget(bool start) {
    if (start == selectingFrom) return;
    setState(() { selectingFrom = start; invalidate(); });
  }

  void choosePlace(Place place, {bool move = true}) {
    setState(() {
      invalidate();
      if (selectingFrom) { from = place; fromText.text = place.name; }
      else { to = place; toText.text = place.name; }
    });
    if (move) mapController.move(place.point, 16);
  }

  Future<void> search({bool reverse = false}) async {
    if (busy) return;
    final target = selectingFrom ? from : to;
    final query = (selectingFrom ? fromText : toText).text.trim();
    if (!reverse && query.isEmpty) {
      setState(() => status = 'Введи улицу и номер дома.'); return;
    }
    if (reverse && target == null) {
      setState(() => status = 'Сначала выбери точку на карте.'); return;
    }
    if (!addresses.configured) {
      setState(() => status = 'Для поиска адресов добавь ключ 2ГИС через кнопку настроек.');
      return;
    }
    final request = ++generation;
    setState(() { busy = true; status = null; results = []; });
    try {
      final found = reverse
          ? await addresses.reverse(target!.point) : await addresses.search(query);
      if (!mounted || generation != request) return;
      setState(() {
        results = found;
        status = found.isEmpty
            ? 'Адрес не найден. Уточни город, улицу и дом или выбери точку на карте.'
            : reverse ? 'Ближайшие найденные объекты — выбери подходящий адрес.' : null;
      });
    } on FormatException catch (e) {
      if (mounted && generation == request) setState(() => status = e.message);
    } catch (_) {
      if (mounted && generation == request) {
        setState(() => status = 'Не удалось получить адреса. Проверь интернет и повтори поиск.');
      }
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  Future<void> settings() async {
    final value = await showDialog<String>(context: context,
      builder: (_) => KeyDialog(initial: addresses.apiKey));
    if (value == null || !mounted) return;
    setState(() { addresses.apiKey = value; invalidate(); });
  }

  void swap() {
    setState(() {
      final previous = from; from = to; to = previous;
      final text = fromText.text; fromText.text = toText.text; toText.text = text;
      invalidate();
    });
  }

  void overview() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Выбранная поездка'),
      content: Text('$transport\n\nОткуда: ${from!.name}\n\nКуда: ${to!.name}\n\n'
        'Это выбранные точки. Построение маршрута, стоимость и бронирование ещё не подключены.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    endDrawer: Drawer(width: MediaQuery.sizeOf(context).width > 440
        ? 400 : MediaQuery.sizeOf(context).width * 0.94,
      child: ProfilePanel(store: widget.store, account: account,
        onAccountChanged: (value) => setState(() => account = value))),
    body: LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return Stack(children: [
        FlutterMap(mapController: mapController,
          options: MapOptions(initialCenter: aktobe, initialZoom: 13, minZoom: 3, maxZoom: 19,
            onTap: (_, point) => choosePlace(Place('Точка: ${coordinates(point)}', point), move: false)),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.intermove.student_prototype'),
            MarkerLayer(markers: [
              if (from != null) marker(from!, 'A', Colors.green.shade700),
              if (to != null) marker(to!, 'B', const Color(0xFF246BFD)),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))]),
          ]),
        SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Align(
          alignment: Alignment.topRight,
          child: Wrap(spacing: 8, children: [
            control('Поиск поездки', Icons.search, () => setState(() => panelVisible = !panelVisible)),
            control('Настройки поиска', Icons.settings_outlined, settings),
            control(account == null ? 'Войти или зарегистрироваться' : 'Профиль: ${account!.name}',
              account == null ? Icons.person_outline : Icons.person,
              () => scaffoldKey.currentState?.openEndDrawer()),
          ]),
        ))),
        if (panelVisible) SafeArea(child: Padding(
          padding: EdgeInsets.fromLTRB(16, wide ? 16 : 80, 16, 40),
          child: Align(alignment: wide ? Alignment.topLeft : Alignment.bottomCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 400,
                maxHeight: wide ? constraints.maxHeight * 0.85 : constraints.maxHeight * 0.60),
              child: Card(margin: EdgeInsets.zero, elevation: 7, color: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: tripPanel())),
            ),
          ),
        )),
        SafeArea(child: Align(alignment: Alignment.centerRight,
          child: Padding(padding: const EdgeInsets.only(right: 16), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              control('Приблизить', Icons.add, () => zoom(1)),
              const SizedBox(height: 8),
              control('Отдалить', Icons.remove, () => zoom(-1)),
              const SizedBox(height: 8),
              control('Показать Актобе', Icons.location_city, () => mapController.move(aktobe, 13)),
            ])))),
      ]);
    }),
  );

  void zoom(double delta) {
    final camera = mapController.camera;
    mapController.move(camera.center, (camera.zoom + delta).clamp(3.0, 19.0).toDouble());
  }

  Marker marker(Place place, String label, Color color) => Marker(
    point: place.point, width: 40, height: 40,
    child: Tooltip(message: place.name, child: CircleAvatar(backgroundColor: color,
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
  );

  Widget control(String tooltip, IconData icon, VoidCallback action) => Material(
    color: Colors.white, elevation: 3, borderRadius: BorderRadius.circular(14),
    child: IconButton(tooltip: tooltip, onPressed: action, icon: Icon(icon)),
  );

  Widget tripPanel() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Icon(Icons.explore, color: Color(0xFF246BFD), size: 30),
      const SizedBox(width: 10),
      const Expanded(child: Text('InterMove', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
      IconButton(tooltip: 'Свернуть панель', onPressed: () => setState(() => panelVisible = false),
        icon: const Icon(Icons.expand_more)),
    ]),
    const Text('Твой город. Твой маршрут.', style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    Wrap(spacing: 6, runSpacing: 6, children: [
      chip('Такси', Icons.local_taxi), chip('Автобус', Icons.directions_bus), chip('Поезд', Icons.train),
    ]),
    const SizedBox(height: 18),
    addressField(true),
    Align(alignment: Alignment.centerRight, child: IconButton(tooltip: 'Поменять местами',
      onPressed: swap, icon: const Icon(Icons.swap_vert))),
    addressField(false),
    const SizedBox(height: 12),
    Text('Сейчас выбираем: ${selectingFrom ? "откуда" : "куда"}. Можно нажать на карту.',
      style: const TextStyle(fontSize: 12, color: Colors.black54)),
    const SizedBox(height: 10),
    Wrap(spacing: 8, children: [
      FilledButton.tonalIcon(onPressed: busy ? null : () => search(),
        icon: const Icon(Icons.search), label: const Text('Найти адрес')),
      TextButton(onPressed: busy ? null : () => search(reverse: true),
        child: const Text('Адрес точки')),
    ]),
    if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
    if (status != null) Padding(padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(status!, style: const TextStyle(fontSize: 13))),
    if (results.isNotEmpty) ...[
      const Divider(),
      const Text('Адреса: 2ГИС', style: TextStyle(fontWeight: FontWeight.bold)),
      ...results.map((place) => ListTile(contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.location_on_outlined), title: Text(place.name),
        trailing: const Icon(Icons.north_west, size: 18), onTap: () => choosePlace(place))),
      TextButton(onPressed: () => launchUrl(Uri.parse('https://2gis.kz/aktobe')),
        child: const Text('Открыть 2ГИС')),
    ],
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(
      onPressed: from == null || to == null ? null : overview,
      icon: const Icon(Icons.arrow_forward), label: const Text('Продолжить'))),
  ]);

  Widget addressField(bool start) => TextField(
    controller: start ? fromText : toText,
    onTap: () => chooseTarget(start),
    onChanged: (_) => setState(() {
      selectingFrom = start;
      if (start) { from = null; } else { to = null; }
      invalidate();
    }),
    onSubmitted: (_) { chooseTarget(start); search(); },
    decoration: InputDecoration(labelText: start ? 'Откуда' : 'Куда',
      hintText: 'Город, улица, дом',
      prefixIcon: Icon(start ? Icons.trip_origin : Icons.location_on_outlined,
        color: start ? Colors.green : const Color(0xFF246BFD)),
      suffixIcon: IconButton(tooltip: start ? 'Выбрать отправление на карте' : 'Выбрать назначение на карте',
        onPressed: () { chooseTarget(start); FocusScope.of(context).unfocus(); },
        icon: Icon(selectingFrom == start ? Icons.touch_app : Icons.map_outlined))),
  );

  Widget chip(String label, IconData icon) => ChoiceChip(label: Text(label),
    avatar: Icon(icon, size: 18), selected: transport == label,
    onSelected: (selected) { if (selected) setState(() => transport = label); });
}

class KeyDialog extends StatefulWidget {
  final String initial;
  const KeyDialog({super.key, required this.initial});
  @override
  State<KeyDialog> createState() => _KeyDialogState();
}
class _KeyDialogState extends State<KeyDialog> {
  late final TextEditingController keyText;
  @override
  void initState() { super.initState(); keyText = TextEditingController(text: widget.initial); }
  @override
  void dispose() { keyText.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Поиск адресов 2ГИС'),
    content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Нужен ключ с доступом к Geocoder API. '
          'Ключ действует в приложении до его закрытия. Карту можно использовать и без ключа.'),
        const SizedBox(height: 16),
        TextField(controller: keyText, obscureText: true, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'API-ключ')),
        const SizedBox(height: 12),
        TextButton(onPressed: () => launchUrl(Uri.parse('https://platform.2gis.ru/')),
          child: const Text('Открыть кабинет 2ГИС')),
        const Text('Поисковые запросы и выбранные для определения адреса координаты отправляются в 2ГИС.'),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () => Navigator.pop(context, keyText.text.trim()), child: const Text('Применить')),
    ],
  );
}
