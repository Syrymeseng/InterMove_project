import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'address_service.dart';
import 'local_store.dart';
import 'profile_panel.dart';
import 'route_service.dart';
import 'transit_service.dart';
import 'demo_dispatch.dart';
import 'auth_service.dart';
import 'journey_hub.dart';
import 'urban_transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalStore? store;
  try { store = await LocalStore.open(); } catch (_) { /* Guest mode remains available. */ }
  runApp(InterMoveApp(store: store));
}
class InterMoveApp extends StatelessWidget {
  final LocalStore? store;
  const InterMoveApp({super.key, this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'InterMove', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48,48))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48,48))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48,48))),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246BFD)),
      inputDecorationTheme: InputDecorationTheme(filled: true,
        fillColor: const Color(0xFFF3F5F9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
    home: HomeScreen(store: store));
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
  final map = MapController();
  final addresses = AddressService();
  final router = RouteService();
  final transit = TransitService();
  final fromText = TextEditingController();
  final toText = TextEditingController();
  late final AuthService auth = AuthService(widget.store, onSessionExpired: () {
    if (mounted) setState(() => account = null);
  });
  Account? get account => auth.account;
  set account(Account? value) => auth.account = value;
  Place? from;
  Place? to;
  bool selectingFrom = true;
  bool localSearch = true;
  bool searchVisible = true;
  List<Place> results = [];
  String? searchMessage;
  bool searching = false;
  int searchGeneration = 0;

  TravelMode mode = TravelMode.taxi;
  bool categories = true;
  bool cycling = false;
  bool wheelchair = false;
  bool pets = false;
  String gender = 'Без разницы';
  int passengers = 1;
  RoadRoute? road;
  RoadRoute? accessWalk;
  RoadRoute? exitWalk;
  List<TransitOption> transitOptions = [];
  TransitOption? selectedTransit;
  bool routing = false;
  String? routeMessage;
  int routeGeneration = 0;
  Timer? routeTimer;
  bool saving = false;
  bool panelsAway = false;
  Timer? panelTimer;
  final Map<bool, Timer> reverseTimers = {};

  void chooseMapPoint(LatLng point) {
    final start = selectingFrom;
    final selected = Place('Точка: ${coordinates(point)}', point);
    choosePlace(selected, move: false);
    reverseTimers[start]?.cancel();
    reverseTimers[start] = Timer(const Duration(milliseconds: 550), () async {
      try {
        if (!mounted || !identical(start ? from : to, selected)) return;
        final matches = await addresses.reverse(point);
        if (!mounted || !identical(start ? from : to, selected)) return;
        final resolved = nearbyAddress(matches, point);
        if (resolved == null) return;
        setState(() {
          if (start) { from = resolved; fromText.text = resolved.name; }
          else { to = resolved; toText.text = resolved.name; }
        });
      } catch (_) { /* Keep the selected coordinates on failure. */ }
    });
  }

  void mapGesture() {
    panelTimer?.cancel();
    if (!panelsAway) setState(() => panelsAway = true);
    panelTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => panelsAway = false);
    });
  }

  Widget slidingPanel(Widget child, double direction) => AnimatedSlide(
    offset: panelsAway ? Offset(direction * .5, 0) : Offset.zero,
    duration: MediaQuery.of(context).disableAnimations
        ? Duration.zero : const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    child: child);

  Future<void> searchDemoDriver() async {
    if (road == null || saving) return;
    if(!auth.remote || account==null) {
      await openBookings('taxi','Profile');
      return;
    }
    final orderKey=requestKey();
    final meters=road!.meters;
    final originName=from!.name, destinationName=to!.name;
    final fare = road!.fare;
    final candidates = matchDemoDrivers(
      gender: pets ? 'Без разницы' : gender, passengers: passengers,
      wheelchair: wheelchair, pets: pets);
    setState(() => saving = true);
    try {
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => DemoDriverSearch(candidates: candidates, fare: fare,onOrder:(driver) async {
          await auth.api('POST','/taxi/demo-order',{'requestKey':orderKey,'driverId':101+demoDrivers.indexOf(driver),
            'origin':originName,'destination':destinationName,'meters':meters,'passengers':passengers,
            'wheelchair':wheelchair,'pets':pets});
        }));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final timer in reverseTimers.values) { timer.cancel(); }
    panelTimer?.cancel(); routeTimer?.cancel(); addresses.close(); router.close(); transit.close();
    auth.close(); map.dispose(); fromText.dispose(); toText.dispose(); super.dispose();
  }
  String meters(double value) => value < 1000 ? '${value.round()} м' : '${(value / 1000).toStringAsFixed(1)} км';
  String minutes(double value) => '${(value / 60).ceil()} мин';
  String coordinates(LatLng p) => '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  bool get endpoints => from != null && to != null;
  bool get paid => mode == TravelMode.taxi || mode == TravelMode.intercity || mode == TravelMode.delivery;

  void clearSearch() { searchGeneration++; results = []; searchMessage = null; }
  void clearRoute() {
    routeTimer?.cancel(); routeGeneration++; road = null; accessWalk = null; exitWalk = null;
    selectedTransit = null; transitOptions = []; routing = false; routeMessage = null;
  }
  void scheduleRoute() {
    if (!endpoints) return;
    routeTimer?.cancel();
    routeTimer = Timer(const Duration(milliseconds: 650), buildRoute);
  }
  void setTarget(bool start) {
    setState(() { selectingFrom = start; clearSearch(); });
  }
  void choosePlace(Place place, {bool move = true}) {
    setState(() {
      clearSearch(); clearRoute();
      if (selectingFrom) { from = place; fromText.text = place.name; selectingFrom = false; }
      else { to = place; toText.text = place.name; }
    });
    if (move) map.move(place.point, 15);
    scheduleRoute();
  }
  void swap() {
    setState(() {
      final previous = from; from = to; to = previous;
      final text = fromText.text; fromText.text = toText.text; toText.text = text;
      clearSearch(); clearRoute();
    });
    scheduleRoute();
  }
  Future<void> openBookings([String initialMode = 'All modes', String initialPage = 'Search']) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => JourneyHub(
      store: widget.store, sharedAuth: auth, initialMode: initialMode, initialPage:initialPage)));
    if (mounted) setState(() {});
  }
  void changeMode(TravelMode value) {
    if(value==TravelMode.bus){
      Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>UrbanTransportPage(auth:auth,from:from?.point,to:to?.point)));
      return;
    }
    if (value == TravelMode.bus || value == TravelMode.rail || value == TravelMode.intercity) {
      openBookings(value == TravelMode.bus ? 'city_bus' : value == TravelMode.rail ? 'train' : 'intercity_bus');
      return;
    }
    setState(() { mode = value; categories = false;
      if (value == TravelMode.delivery || pets) gender = 'Без разницы';
      clearRoute(); });
    scheduleRoute();
  }
  Future<void> search({bool reverse = false}) async {
    if (searching) return;
    final point = selectingFrom ? from : to;
    final query = (selectingFrom ? fromText : toText).text.trim();
    if ((!reverse && query.isEmpty) || (reverse && point == null)) {
      setState(() => searchMessage = reverse ? 'Сначала выбери точку на карте.' : 'Введи город и адрес.');
      return;
    }
    final request = ++searchGeneration;
    setState(() { searching = true; results = []; searchMessage = null; });
    try {
      final found = reverse ? await addresses.reverse(point!.point) : await addresses.search(query, local: localSearch);
      if (!mounted || request != searchGeneration) return;
      setState(() {
        results = found;
        searchMessage = found.isEmpty ? 'Адрес не найден. Можно выбрать точку на карте.' : null;
      });
    } on FormatException catch (e) {
      if (mounted && request == searchGeneration) setState(() => searchMessage = e.message);
    } catch (_) {
      if (mounted && request == searchGeneration) setState(() => searchMessage = 'Ошибка поиска. Проверь интернет.');
    } finally { if (mounted) setState(() => searching = false); }
  }

  Future<void> buildRoute() async {
    routeTimer?.cancel();
    if (!endpoints) return;
    final request = ++routeGeneration;
    final a = from!.point; final b = to!.point;
    final selectedMode = mode;
    setState(() { routing = true; road = null; accessWalk = null; exitWalk = null;
      routeMessage = null; transitOptions = []; selectedTransit = null; });
    try {
      if (isTransit(selectedMode)) {
        final lines = await transit.nearby(a, selectedMode == TravelMode.rail);
        if (!mounted || request != routeGeneration) return;
        final options = findTransitOptions(lines, a, b);
        setState(() {
          transitOptions = options;
          if (options.isEmpty) routeMessage =
            'В открытых данных не найден подходящий прямой маршрут с остановками рядом с A и B. '
            'Это не означает, что транспорта нет: данные могут быть неполными.';
        });
      } else {
        final result = await router.route(a, b, routeProfile(selectedMode, cycling));
        if (!mounted || request != routeGeneration) return;
        setState(() => road = result);
      }
    } on FormatException catch (e) {
      if (mounted && request == routeGeneration) setState(() => routeMessage = e.message);
    } catch (_) {
      if (mounted && request == routeGeneration) setState(() => routeMessage = 'Не удалось построить маршрут. Проверь интернет и повтори.');
    } finally {
      if (mounted && request == routeGeneration) setState(() => routing = false);
    }
  }

  Future<void> selectTransit(TransitOption option) async {
    if (!endpoints) return;
    final request = ++routeGeneration;
    final a = from!.point; final b = to!.point;
    setState(() { selectedTransit = option; accessWalk = null; exitWalk = null;
      routing = true; routeMessage = null; });
    try {
      final first = await walkingLeg(a, option.first.point);
      if (!mounted || request != routeGeneration) return;
      final last = await walkingLeg(option.last.point, b);
      if (!mounted || request != routeGeneration) return;
      setState(() {
        accessWalk = first; exitWalk = last;
        if (first.meters > 2500 || last.meters > 2500) {
          routeMessage = 'По дорожкам до остановки далеко. Попробуй другой вариант.';
        }
      });
    } on FormatException catch (e) {
      if (mounted && request == routeGeneration) setState(() => routeMessage = e.message);
    } catch (_) {
      if (mounted && request == routeGeneration) setState(() => routeMessage = 'Не удалось проверить пешие участки. Выбери другой вариант или повтори.');
    } finally { if (mounted && request == routeGeneration) setState(() => routing = false); }
  }
  Future<RoadRoute> walkingLeg(LatLng a, LatLng b) async {
    if (const Distance()(a, b) < 2) return RoadRoute([a], 0, 0, 'foot-walking');
    return router.route(a, b, 'foot-walking');
  }

  Future<void> settings() async {
    final key = await showDialog<String>(context: context, builder: (_) => RoutingSettings(initial: router.apiKey, auth: auth));
    if (!mounted || key == null) return;
    setState(() { router.apiKey = key; clearRoute(); });
    scheduleRoute();
  }
  Future<void> saveDraft() async {
    if (road == null || !paid || saving || widget.store == null) return;
    final payload = <String, dynamic>{
      'mode': mode.name, 'from': from!.name, 'to': to!.name,
      'a': [from!.point.latitude, from!.point.longitude],
      'b': [to!.point.latitude, to!.point.longitude],
      'meters': road!.meters, 'fareKzt': road!.fare,
      'wheelchair': mode == TravelMode.delivery ? false : wheelchair,
      'pets': mode == TravelMode.delivery ? false : pets,
      'driverGenderPreference': mode == TravelMode.delivery || pets ? 'Без разницы' : gender,
      'passengers': mode == TravelMode.delivery ? 0 : passengers,
      'status': 'local_demo_draft',
    };
    setState(() => saving = true);
    try {
      final id = widget.store!.saveDraft(account?.id, payload);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text('Заявка №$id сохранена'),
        content: const Text('Это локальная демонстрационная заявка. Водитель или курьер не вызван; оплата не списана.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))]));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось сохранить заявку.')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    endDrawer: Drawer(width: MediaQuery.sizeOf(context).width > 440 ? 400 : MediaQuery.sizeOf(context).width * .94,
      child: ProfilePanel(auth: auth, account: account,
        onAccountChanged: (value) => setState(() => account = value))),
    body: LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1050;
      return Stack(children: [
        FlutterMap(mapController: map, options: MapOptions(initialCenter: aktobe, initialZoom: 13,
          minZoom: 3, maxZoom: 19,
          onPositionChanged: (_, hasGesture) { if (hasGesture) mapGesture(); },
          onTap: (_, p) => chooseMapPoint(p)),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kz.intermove.student_prototype'),
            PolylineLayer(polylines: [
              if (road != null) Polyline(points: road!.points, strokeWidth: 6, color: const Color(0xFF246BFD)),
              if (accessWalk != null) Polyline(points: accessWalk!.points, strokeWidth: 5, color: Colors.green),
              if (exitWalk != null) Polyline(points: exitWalk!.points, strokeWidth: 5, color: Colors.green),
              // Thin orange line is explicitly schematic, not a road shape.
              if (selectedTransit != null) Polyline(points: selectedTransit!.schematic,
                strokeWidth: 2, color: Colors.orange.shade800),
            ]),
            MarkerLayer(markers: [
              if (from != null) marker(from!.point, 'A', from!.name, Colors.green.shade700),
              if (to != null) marker(to!.point, 'B', to!.name, const Color(0xFF246BFD)),
              if (selectedTransit != null) ...[
                marker(selectedTransit!.first.point, '↑', selectedTransit!.first.name, Colors.orange.shade800),
                marker(selectedTransit!.last.point, '↓', selectedTransit!.last.name, Colors.orange.shade800),
              ],
            ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
              TextSourceAttribution('Routing: openrouteservice / HeiGIT', onTap: () => launchUrl(Uri.parse('https://openrouteservice.org/'))),
            ]),
          ]),
        Positioned(top: 16, right: 16, left:wide ? 390 : 16, child: SafeArea(child: Wrap(alignment:WrapAlignment.end,spacing: 8, children: [
          control('История такси', Icons.local_taxi_outlined, () => openBookings('All modes','Drivers')),
          control('Уведомления', Icons.notifications_outlined, () => openBookings('All modes','Notifications')),
          control('Билеты и поездки / Book journeys', Icons.confirmation_number_outlined, () => openBookings()),
          control('Поиск', Icons.search, () => setState(() => searchVisible = !searchVisible)),
          control('Настройки', Icons.settings_outlined, settings),
          control('Профиль', account == null ? Icons.person_outline : Icons.person,
            () => scaffoldKey.currentState?.openEndDrawer()),
        ]))),
        if (searchVisible) Positioned(top: wide ? 16 : 78, left: 16,
          width: wide ? 350 : box.maxWidth - 32,
          child: SafeArea(child: ConstrainedBox(constraints: BoxConstraints(
            maxHeight: wide ? box.maxHeight - 70 : box.maxHeight * .34),
            child: slidingPanel(surface(searchPanel()), -1)))),
        Positioned(right: 16, bottom: 38,
          width: wide ? (box.maxWidth - 420).clamp(360.0, 660.0).toDouble() : box.maxWidth - 32,
          child: SafeArea(top: false, child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * (wide ? .48 : .40)),
            child: slidingPanel(surface(transportPanel()), 1)))),
        Positioned(right: 16, top: wide ? 88 : box.maxHeight * .48,
          child: Column(children: [
            control('Приблизить', Icons.add, () => zoom(1)),
            const SizedBox(height: 6),
            control('Отдалить', Icons.remove, () => zoom(-1)),
            const SizedBox(height: 6),
            control('Показать Актобе', Icons.location_city, () => map.move(aktobe, 13)),
          ])),
      ]);
    }),
  );
  Widget surface(Widget child) => Card(margin: EdgeInsets.zero, color: Colors.white,
    surfaceTintColor: Colors.transparent, elevation: 7,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: child));
  Widget control(String title, IconData icon, VoidCallback action) => Material(
    color: Colors.white, elevation: 2, borderRadius: BorderRadius.circular(14),
    child: IconButton(tooltip: title, onPressed: action, icon: Icon(icon)));
  void zoom(double delta) => map.move(map.camera.center, (map.camera.zoom + delta).clamp(3.0, 19.0).toDouble());
  Marker marker(LatLng p, String label, String title, Color color) {
    var style = 'pin';
    try { style = widget.store?.setting('marker') ?? 'pin'; } catch (_) {}
    return Marker(point: p, width: 48, height: 48,
      child: Semantics(label: title, child: Tooltip(message: title,
        child: Container(alignment: Alignment.center,
          decoration: BoxDecoration(color: color,
            borderRadius: BorderRadius.circular(style == 'circle' ? 24 : style == 'flag' ? 2 : 12),
            border: Border.all(color: Colors.white, width: 2)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))));
  }

  Widget searchPanel() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Icon(Icons.explore, color: Color(0xFF246BFD)), const SizedBox(width: 8),
      const Expanded(child: Text('InterMove', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))),
      IconButton(onPressed: () => setState(() => searchVisible = false), tooltip: 'Скрыть поиск', icon: const Icon(Icons.close))]),
    const SizedBox(height: 12), addressField(true),
    Align(alignment: Alignment.centerRight, child: IconButton(onPressed: swap,
      tooltip: 'Поменять A и B', icon: const Icon(Icons.swap_vert))),
    addressField(false), const SizedBox(height: 10),
    Text('На карте выбираем ${selectingFrom ? "A — отправление" : "B — назначение"}.',
      style: const TextStyle(fontSize: 12, color: Colors.black54)),
    Wrap(spacing: 6, children: [
      TextButton.icon(onPressed: searching ? null : () => search(), icon: const Icon(Icons.search), label: const Text('Найти адрес')),
      TextButton(onPressed: searching ? null : () => search(reverse: true), child: const Text('Адрес точки'))]),
    CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true,
      title: const Text('Искать только в Актобе'), value: localSearch,
      onChanged: (v) => setState(() { localSearch = v ?? true; clearSearch(); })),
    if (searching) const LinearProgressIndicator(),
    if (searchMessage != null) Text(searchMessage!),
    ...results.map((p) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.location_on_outlined),
      title: Text(p.name), onTap: () => choosePlace(p))),
    if (results.isNotEmpty) const Text('Photon · данные OpenStreetMap', style: TextStyle(fontSize: 11)),
  ]);
  Widget addressField(bool start) => TextField(controller: start ? fromText : toText,
    onTap: () => setTarget(start), onSubmitted: (_) { setTarget(start); search(); },
    onChanged: (_) => setState(() {
      selectingFrom = start; if (start) { from = null; } else { to = null; }
      clearSearch(); clearRoute();
    }),
    decoration: InputDecoration(labelText: start ? 'A · Откуда' : 'B · Куда', hintText: 'Актобе, улица, дом',
      suffixIcon: IconButton(tooltip: 'Выбрать на карте', onPressed: () {
        setTarget(start); FocusScope.of(context).unfocus();
      }, icon: Icon(selectingFrom == start ? Icons.touch_app : Icons.map_outlined))));

  IconData modeIcon(TravelMode value) => switch(value) {
    TravelMode.taxi => Icons.local_taxi, TravelMode.bus => Icons.directions_bus,
    TravelMode.rail => Icons.train, TravelMode.intercity => Icons.add_road,
    TravelMode.delivery => Icons.local_shipping_outlined, TravelMode.active => Icons.directions_walk,
  };
  Widget transportPanel() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(categories ? 'Как поедем?' : modeLabel(mode),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      if (!categories) TextButton.icon(onPressed: () => setState(() => categories = true),
        icon: const Icon(Icons.apps), label: const Text('Все виды'))]),
    const SizedBox(height: 8),
    AnimatedSize(duration: const Duration(milliseconds: 300), alignment: Alignment.topCenter,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation,
          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .13), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)), child: child)),
        child: categories ? categoryCards() : Column(key: ValueKey(mode), crossAxisAlignment: CrossAxisAlignment.start,
          children: [modeSettings(), const SizedBox(height: 8), routeDetails()]))),
    if (categories) Padding(padding: const EdgeInsets.only(top: 10), child: Text(
      endpoints ? 'Выбери вид поездки. По умолчанию рассчитывается такси.' : 'Сначала выбери A и B на карте или через поиск.',
      style: const TextStyle(color: Colors.black54))),
  ]);
  Widget categoryCards() => SizedBox(key: const ValueKey('categories'), height: 100 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 56) * 4,
    child: ListView.separated(scrollDirection: Axis.horizontal,
      itemCount: TravelMode.values.length, separatorBuilder: (_, index) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        final item = TravelMode.values[i];
        return SizedBox(width: 120, child: Material(color: const Color(0xFFF1F5FF),
          borderRadius: BorderRadius.circular(18), child: InkWell(borderRadius: BorderRadius.circular(18),
            onTap: () => changeMode(item), child: Padding(padding: const EdgeInsets.all(12), child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [Icon(modeIcon(item), size: 30,
                color: const Color(0xFF246BFD)), const SizedBox(height: 8), Text(modeLabel(item), textAlign: TextAlign.center)])))));
      }));

  Widget modeSettings() {
    if (mode == TravelMode.active) return Wrap(spacing: 8, children: [
      ChoiceChip(label: const Text('Пешком'), avatar: const Icon(Icons.directions_walk), selected: !cycling,
        onSelected: (_) { setState(() { cycling = false; clearRoute(); }); scheduleRoute(); }),
      ChoiceChip(label: const Text('Велосипед'), avatar: const Icon(Icons.directions_bike), selected: cycling,
        onSelected: (_) { setState(() { cycling = true; clearRoute(); }); scheduleRoute(); }),
    ]);
    if (isTransit(mode)) return const Text(
      'Прямые маршруты из OpenStreetMap. Без расписания, пересадок и движения онлайн.',
      style: TextStyle(fontSize: 12, color: Colors.black54));
    if (mode == TravelMode.delivery) return const Text('Доставка на автомобиле · учебный тариф 350 ₸ / 500 м.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (mode == TravelMode.intercity) const Text('Междугородняя поездка на автомобиле'),
      Text(wheelchair && pets ? 'Коляска + животное' : wheelchair ? 'Перевозка в коляске'
        : pets ? 'С животным' : 'Стандартная поездка'),
      ExpansionTile(key: ValueKey('options-${mode.name}'), tilePadding: EdgeInsets.zero,
        title: const Text('Дополнительные параметры'),
        children: [
          SwitchListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Перевозка в коляске'), value: wheelchair,
            onChanged: (v) => setState(() => wheelchair = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Поездка с животным'), value: pets,
            onChanged: (v) => setState(() {
              pets = v; if (v) gender = 'Без разницы';
            })),
          if (!pets) ...[
            const Text('Предпочтение по водителю'),
            Wrap(spacing: 8, children: ['Без разницы', 'Женщина', 'Мужчина']
              .map((v) => ChoiceChip(label: Text(v), selected: gender == v,
                onSelected: (_) => setState(() => gender = v))).toList()),
          ],
          Row(children: [const Text('Пассажиры: '),
            DropdownButton<int>(value: passengers,
              items: [1, 2, 3, 4].map((n) => DropdownMenuItem(value: n,
                child: Text('$n'))).toList(),
              onChanged: (v) => setState(() => passengers = v ?? 1))]),
          const Text('Доступность проверяется только по вымышленным водителям. '
            'Полная проверка доступности маршрута появится на следующем этапе.',
            style: TextStyle(fontSize: 12)),
        ]),
    ]);
  }

  Widget routeDetails() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (!endpoints) const Text('Выбери точки A и B.'),
    if (routing) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator()),
    if (routeMessage != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(routeMessage!)),
    if (road != null) ...[
      Wrap(spacing: 18, runSpacing: 8, children: [
        Text(meters(road!.meters), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text('≈ ${minutes(road!.seconds)}', style: const TextStyle(fontSize: 22)),
        Text(paid ? '${road!.fare.toStringAsFixed(2)} ₸' : 'Без тарифа', style: const TextStyle(fontSize: 22, color: Color(0xFF246BFD))),
      ]),
      const Text('Оценка времени без текущих пробок.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      if (paid) const Text('0,70 ₸ за метр (350 ₸ / 500 м). Без доплат.', style: TextStyle(fontSize: 12)),
      if (mode == TravelMode.active) const Text('Учитываются доступные пути выбранного режима по данным карты.', style: TextStyle(fontSize: 12)),
      if (paid) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(
        onPressed: saving ? null : mode == TravelMode.delivery
          ? (widget.store == null ? null : saveDraft) : searchDemoDriver, icon: const Icon(Icons.check),
        label: Text(saving ? 'Подождите…' : mode == TravelMode.delivery
          ? 'Сохранить заявку · демо' : 'Найти водителя · демо'))),
      if (mode == TravelMode.delivery && widget.store == null) const Text('Локальная база недоступна: сохранить заявку нельзя.'),
    ],
    if (isTransit(mode)) ...[
      ...transitOptions.map((option) => ListTile(contentPadding: EdgeInsets.zero,
        leading: Icon(mode == TravelMode.bus ? Icons.directions_bus : Icons.tram),
        title: Text('${option.line.name} · ${option.line.direction}'),
        subtitle: Text('${option.first.name} → ${option.last.name}\n'
          'До/после остановок по прямой: ${meters(option.accessMeters)} / ${meters(option.exitMeters)}'),
        selected: identical(selectedTransit, option), onTap: routing ? null : () => selectTransit(option))),
      if (selectedTransit != null) ...[
        const Divider(),
        Text('1. Пешком до «${selectedTransit!.first.name}»'
          '${accessWalk == null ? " — путь ещё не проверен" : " · ${meters(accessWalk!.meters)}, ${minutes(accessWalk!.seconds)}"}'),
        Text('2. Сесть на ${selectedTransit!.line.name}, выйти на «${selectedTransit!.last.name}».'),
        Text('3. Пешком до B'
          '${exitWalk == null ? " — путь ещё не проверен" : " · ${meters(exitWalk!.meters)}, ${minutes(exitWalk!.seconds)}"}'),
        const Text('Оранжевая линия — схема остановок, не точная трасса. Зелёные участки — пешие пути. '
          'Тариф и время прибытия транспорта неизвестны.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    ],
    if (endpoints) TextButton.icon(onPressed: routing ? null : buildRoute,
      icon: const Icon(Icons.refresh), label: Text(isTransit(mode) ? 'Найти варианты' : 'Пересчитать маршрут')),
  ]);
}

class RoutingSettings extends StatefulWidget {
  final String initial;
  final AuthService auth;
  const RoutingSettings({super.key, required this.initial, required this.auth});
  @override
  State<RoutingSettings> createState() => _RoutingSettingsState();
}
class _RoutingSettingsState extends State<RoutingSettings> {
  late final TextEditingController keyText;
  late final TextEditingController serverText;
  String? status;
  bool checking=false;
  Future<void> check() async {
    setState((){checking=true;status=null;});
    try{await widget.auth.checkConnection(serverText.text);if(mounted)setState(()=>status="Сервер доступен.");}
    catch(_){if(mounted)setState(()=>status="Нет соединения. Запустите Python-сервер и проверьте адрес.");}
    finally{if(mounted)setState(()=>checking=false);}
  }
  void apply(){
    try{widget.auth.configure(serverText.text);Navigator.pop(context,keyText.text.trim());}
    catch(e){setState(()=>status=e is FormatException?e.message:"Не удалось сохранить настройки.");}
  }
  @override
  void initState() { super.initState(); keyText = TextEditingController(text: widget.initial);serverText=TextEditingController(text:widget.auth.endpoint); }
  @override
  void dispose() { keyText.dispose();serverText.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Настройки приложения'),
    content: SizedBox(width: 390, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller:serverText,decoration:const InputDecoration(labelText:'Адрес сервера бронирования',hintText:'https://… или http://127.0.0.1:8787')),
      const Text('На Windows/Mac по умолчанию используется сервер на этом компьютере. Для телефона укажите общий HTTPS. Адрес сохраняется; при смене потребуется войти заново.'),
      TextButton(onPressed:checking?null:check,child:Text(checking?'Проверяем…':'Проверить соединение')),
      if(status!=null) Semantics(liveRegion:true,child:Text(status!)),
      const SizedBox(height:16),
      const Text('Photon: ключ не нужен.\n\nМаршруты: openrouteservice. Ключ можно добавить позже; '
        'карта, профили и поиск адресов работают без него.'),
      const SizedBox(height: 16),
      TextField(controller: keyText, obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Ключ openrouteservice', hintText: 'Пока можно оставить пустым')),
      const SizedBox(height: 12),
      const Text('Ключ из этого окна хранится только до закрытия приложения.'),
      TextButton(onPressed: () => launchUrl(Uri.parse('https://account.heigit.org/')),
        child: const Text('Кабинет openrouteservice')),
      Text('Адреса отправляются в Photon, точки маршрута — в openrouteservice, '
        'область поиска транспорта — в Overpass. '
        '${widget.auth.remote ? "Профиль хранится на общем сервере." : "Профиль хранится на устройстве."}',
        style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: checking?null:apply, child: const Text('Применить')),
    ]);
}
