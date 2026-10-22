import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';
import 'local_store.dart';
import 'transit_map.dart';

typedef Json = Map<String, dynamic>;
String requestKey() => List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
String localTime(num seconds) {
  final d = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true).add(const Duration(hours: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)} UTC+05';
}
String kzt(num cents) => '${(cents / 100).toStringAsFixed(2)} ₸';
List<Json> objects(dynamic list) => (list as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)).toList();
String failure(Object e) => e is FormatException ? e.message : 'Connection failed. Your input is retained; retry the same operation.';

class Words {
  final String locale;
  const Words(this.locale);
  String call(String english) => (_words[english]?[locale == 'ru' ? 0 : 1] ?? english) == english || locale == 'en'
    ? english : _words[english]![locale == 'ru' ? 0 : 1];
  static const _words = <String,List<String>>{
    'Search':['Поиск','Іздеу'], 'Bookings':['Поездки','Сапарлар'], 'Notifications':['Уведомления','Хабарламалар'],
    'Profile':['Профиль','Профиль'], 'Management':['Управление','Басқару'], 'Delivery':['Доставка','Жеткізу'],
    'Drivers':['Водители','Жүргізушілер'], 'Map':['Карта','Карта'], 'Refresh':['Обновить','Жаңарту'],
    'Origin':['Откуда','Қайдан'], 'Destination':['Куда','Қайда'], 'Passengers':['Пассажиры','Жолаушылар'],
    'Departure':['Отправление','Жөнелту'], 'Find journeys':['Найти поездки','Сапар іздеу'],
    'Additional parameters':['Дополнительные параметры','Қосымша параметрлер'],
    'Step-free access':['Без ступенек','Баспалдақсыз'], 'Boarding assistance':['Помощь при посадке','Отыруға көмек'],
    'Wheelchair':['Коляска','Арба'], 'none':['Нет','Жоқ'], 'folded':['Складная','Жиналмалы'], 'seated':['Оставаться в коляске','Арбада отыру'],
    'Pet-friendly':['С животным','Жануармен'], 'Carrier':['В переноске','Тасымалдағышта'],
    'Driver preference':['Пол водителя','Жүргізуші жынысы'], 'any':['Без разницы','Бәрібір'], 'woman':['Женщина','Әйел'], 'man':['Мужчина','Ер'],
    'city_bus':['Городской автобус','Қалалық автобус'], 'intercity_bus':['Междугородний автобус','Қалааралық автобус'],
    'metro':['Метро','Метро'], 'tram':['Трамвай','Трамвай'], 'lrt':['LRT','LRT'],
    'train':['Поезд','Пойыз'], 'taxi':['Такси','Такси'], 'All modes':['Все виды','Барлық түрі'],
    'Transfer buffer':['Время пересадки','Ауысу уақыты'], 'Sort':['Сортировка','Сұрыптау'],
    'fare':['Цена','Баға'], 'duration':['Длительность','Ұзақтығы'], 'Choose':['Выбрать','Таңдау'],
    'Sign in':['Войти','Кіру'], 'Register':['Регистрация','Тіркелу'], 'Sign out':['Выйти','Шығу'],
    'Name':['Имя','Аты'], 'Email':['Email','Email'], 'Password':['Пароль','Құпиясөз'],
    'Save':['Сохранить','Сақтау'], 'Cancel':['Отмена','Болдырмау'], 'Close':['Закрыть','Жабу'],
    'Save preferences':['Сохранить предпочтения','Қалауларды сақтау'], 'Remove preferences':['Удалить предпочтения','Қалауларды жою'],
    'Language':['Язык','Тіл'], 'Currency':['Валюта','Валюта'], 'Avatar frame':['Рамка аватара','Аватар жақтауы'],
    'Marker style':['Стиль метки','Белгі стилі'], 'History':['История','Тарих'], 'Upcoming':['Предстоящие','Алдағы'],
    'Open':['Открыть','Ашу'], 'Cancel booking':['Отменить поездку','Сапардан бас тарту'],
    'Replace journey':['Заменить поездку','Сапарды ауыстыру'], 'Alternatives':['Альтернативы','Баламалар'],
    'Checkout':['Оформление','Рәсімдеу'], 'Lead traveller':['Основной пассажир','Негізгі жолаушы'],
    'Contact email':['Контактный email','Байланыс email'], 'Reserve for 5 minutes':['Резерв на 5 минут','5 минутқа бронь'],
    'Confirm mock payment':['Подтвердить тестовую оплату','Сынақ төлемін растау'],
    'approved':['Успешно','Сәтті'], 'declined':['Отказ','Қабылданбады'], 'timeout':['Тайм-аут','Уақыт аяқталды'],
    'approved_then_failed':['Сбой после одобрения','Мақұлдаудан кейінгі қате'],
    'No items':['Пока пусто','Әзірге бос'], 'No matching journey':['Подходящей поездки нет','Сәйкес сапар жоқ'],
    'DEMO — no real ticket or charge':['ДЕМО — без реальных билетов и списаний','ДЕМО — нақты билет пен төлем жоқ'],
  };
}

class JourneyHub extends StatefulWidget {
  final LocalStore? store;
  final AuthService sharedAuth;
  final String initialMode;
  final String initialPage;
  const JourneyHub({super.key, required this.store, required this.sharedAuth, this.initialMode = 'All modes', this.initialPage = 'Search'});
  @override State<JourneyHub> createState() => _JourneyHubState();
}
class _JourneyHubState extends State<JourneyHub> {
  AuthService get auth => widget.sharedAuth;
  String page='Search', locale='en', currency='KZT', avatar='plain', marker='pin';
  bool busy=false, registering=false, history=false;
  String? error;
  Json? catalog;
  List<Json> results=[], bookings=[], notifications=[], drivers=[], services=[], parcels=[];
  Json? management, selectedRoute;
  List<Json> taxiTrips=[];
  Timer? refreshTimer;
  bool polling=false;
  bool includeUrban=false;
  int get unread=>notifications.where((n)=>n['unread']==1).length;
  Future<void> poll() async {
    if(!mounted || busy || polling || !signed || !auth.remote)return;
    polling=true;
    try {
      final n=await auth.api('GET','/notifications');
      if(mounted)setState(()=>notifications=objects(n['notifications']));
      if(page=='Drivers')await reloadPage();
    }catch(_) {} finally{polling=false;}
  }
  void go(String target){setState(()=>page=target);run(reloadPage);}
  int origin=1, destination=4, passengers=1, buffer=15;
  String mode='All modes', sort='fare';
  late final TextEditingController departure=TextEditingController();
  final name=TextEditingController(), email=TextEditingController(), password=TextEditingController();
  Json need={};
  Words get tr => Words(locale);
  bool get signed => auth.account != null;
  bool get staff => ['admin','operator'].contains(auth.account?.role);
  @override void initState() {
    super.initState();
    mode=widget.initialMode;page=widget.initialPage;
    if(mode=='city_bus')destination=2;
    if(mode=='train'){origin=2;destination=702;}
    if(mode=='intercity_bus'){origin=701;destination=703;}
    refreshTimer=Timer.periodic(const Duration(seconds:15),(_)=>poll());
    if(auth.account!=null){name.text=auth.account!.name;email.text=auth.account!.login;
      need={for(final k in ['stepFree','boardingAssistance','wheelchair']) if(auth.account!.preferences.containsKey(k)) k:auth.account!.preferences[k]};}
    try { locale=widget.store?.setting('locale') ?? 'en'; currency=widget.store?.setting('currency') ?? 'KZT';
      avatar=widget.store?.setting('avatar') ?? 'plain'; marker=widget.store?.setting('marker') ?? 'pin'; } catch (_) {}
    if(auth.remote) load();
  }
  @override void dispose() { refreshTimer?.cancel(); departure.dispose(); name.dispose(); email.dispose(); password.dispose(); super.dispose(); }
  Future<void> run(Future<void> Function() action) async {
    if(busy) return;
    setState(() {busy=true; error=null;});
    try {await action();} catch(e) {if(mounted) setState(() => error=failure(e));}
    finally {if(mounted) setState(() => busy=false);}
  }
  void remember(String key,String value) {
    try {widget.store?.saveSetting(key,value);} catch (_) {}
  }
  Future<void> load() => run(() async {
    final c=await auth.api('GET','/catalog');
    if(!mounted) return;
    setState(() {catalog=c; if(departure.text.isEmpty) departure.text=localTime(c['demoDeparture'] as num).replaceAll(' UTC+05','');});
    await reloadPage();
  });
  Future<void> reloadPage() async {
    if(!signed) return;
    if(page=='Bookings') bookings=objects((await auth.api('GET','/bookings'))['bookings']);
    notifications=objects((await auth.api('GET','/notifications'))['notifications']);
    if(page=='Drivers') {final h=await auth.api('GET','/taxi/history');drivers=objects(h['drivers']);taxiTrips=objects(h['trips']);}
    if(page=='Delivery') parcels=objects((await auth.api('GET','/parcels'))['parcels']);
    if(page=='Management' && staff) {
      services=objects((await auth.api('GET','/manage/services'))['services']);
      if(auth.account!.role=='admin') {management=await auth.api('GET','/manage/catalog');management!['taxiRequests']=(await auth.api('GET','/manage/taxi-requests'))['requests'];}
    }
    if(mounted) setState(() {});
  }
  Json searchQuery() {
    final d=DateTime.tryParse('${departure.text.trim().replaceFirst(' ','T')}:00+05:00');
    if(d==null) throw const FormatException('Departure format: YYYY-MM-DD HH:mm (UTC+05).');
    return {'origin':origin,'destination':destination,'passengers':passengers,
      'departure':d.millisecondsSinceEpoch/1000,'buffer':buffer,'needs':need,'sort':sort,
      'modes':mode=='All modes'?['city_bus','intercity_bus','train','taxi',if(includeUrban)...['metro','tram','lrt']]:[mode]};
  }
  Future<void> search() => run(() async {
    final data=await auth.api('POST','/search',searchQuery());
    if(mounted) setState(() {results=objects(data['options']);selectedRoute=results.isEmpty?null:results.first;});
    if(results.isEmpty && mounted) setState(() => error=tr('No matching journey')+'. '+(data['message'] as String? ?? ''));
  });
  Future<void> login() => run(() async {
    if(registering) await auth.register(name.text,email.text,password.text);
    else await auth.login(email.text,password.text);
    password.clear();
    final a=auth.account!; name.text=a.name; email.text=a.login;
    final prefs=a.preferences;
    need={for(final key in ['stepFree','boardingAssistance','wheelchair']) if(prefs.containsKey(key)) key:prefs[key]};
    locale=prefs['locale'] as String? ?? locale; currency=prefs['currency'] as String? ?? currency;
    avatar=prefs['avatar'] as String? ?? avatar; marker=prefs['marker'] as String? ?? marker;
    for(final entry in {'locale':locale,'currency':currency,'avatar':avatar,'marker':marker}.entries) {remember(entry.key,entry.value);}
  });
  Future<void> saveProfile(bool remove) => run(() async {
    await auth.updateProfile(name.text, remove?{}:{
      for(final key in ['stepFree','boardingAssistance','wheelchair']) if(need.containsKey(key)) key:need[key],
      'locale':locale,'currency':currency,'avatar':avatar,'marker':marker});
    if(remove) need={};
  });
  Json? pendingCheckout() {
    try {
      final raw=widget.store?.setting('pending_checkout');
      if(raw==null || raw.isEmpty)return null;
      final saved=jsonDecode(raw) as Json;
      return saved['accountId']==auth.account?.id && saved['backend']==auth.endpoint?saved:null;
    }catch(_){return null;}
  }
  Future<void> checkout(Json option,{String? replace}) async {
    if(!signed) {setState(() {page='Profile';error='Sign in before placing a booking.';});return;}
    final pending=pendingCheckout();
    final selected=pending==null?option:Map<String,dynamic>.from(pending['request'] as Map);
    final result=await Navigator.push<Json>(context, MaterialPageRoute(builder: (_) => CheckoutPage(
      auth:auth, option:selected, replace:pending==null?replace:selected['replace'] as String?, words:tr,resume:pending)));
    if(!mounted) return;
    if(result!=null) await showBooking(result);
    if(mounted) await run(reloadPage);
  }
  String money(num cents) {
    final rates={'KZT':1.0,'USD':.002,'EUR':.0018};
    return currency=='KZT'?kzt(cents):'≈ ${(cents/100*rates[currency]!).toStringAsFixed(2)} $currency · ${kzt(cents)}';
  }
  Widget select<T>(String label,T value,List<T> values,ValueChanged<T> change,{String Function(T)? display}) =>
    DropdownButtonFormField<T>(value:value, key:ValueKey('$label:$value'), isExpanded:true,
      decoration:InputDecoration(labelText:tr(label)), items:values.map((v)=>DropdownMenuItem<T>(value:v,
        child:Text(display?.call(v) ?? tr('$v'),overflow:TextOverflow.ellipsis,maxLines:1))).toList(),
      onChanged:busy?null:(v){if(v!=null)setState((){change(v);if(page=='Search'){results=[];selectedRoute=null;}});});
  Widget button(String text,VoidCallback action,{IconData icon=Icons.chevron_right}) => Padding(
    padding:const EdgeInsets.symmetric(vertical:4),child:FilledButton.icon(onPressed:busy?null:action,
      icon:Icon(icon),label:Text(tr(text))));
  Widget card(Widget child) => Card(child:Padding(padding:const EdgeInsets.all(16),child:child));
  Widget column(List<Widget> children) => Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children);
  Widget needControls() => column([
    for(final key in ['stepFree','boardingAssistance']) SwitchListTile(contentPadding:EdgeInsets.zero,
      title:Text(tr(key=='stepFree'?'Step-free access':'Boarding assistance')),value:need[key]==true,
      onChanged:busy?null:(v)=>setState((){need[key]=v;results=[];selectedRoute=null;})),
    select<String>('Wheelchair',need['wheelchair'] as String? ?? 'none',['none','folded','seated'],(v)=>need['wheelchair']=v),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(tr('Pet-friendly')),value:need['pets']==true,
      onChanged:busy?null:(v)=>setState(() {results=[];selectedRoute=null;need['pets']=v; if(v) {need['gender']='any';need['petType']??='cat';need['petSize']??='small';}})),
    if(need['pets']==true) ...[
      select<String>('Pet type',need['petType'] as String? ?? 'cat',['cat','dog','small_pet'],(v)=>need['petType']=v),
      select<String>('Pet size',need['petSize'] as String? ?? 'small',['small','medium','large'],(v)=>need['petSize']=v),
      SwitchListTile(title:Text(tr('Carrier')),value:need['carrier']==true,onChanged:busy?null:(v)=>setState((){need['carrier']=v;results=[];selectedRoute=null;})),
    ] else select<String>('Driver preference',need['gender'] as String? ?? 'any',['any','woman','man'],(v)=>need['gender']=v),
    if(need['driverId']!=null) TextButton(onPressed:()=>setState(()=>need.remove('driverId')),child:Text('Favourite driver #${need['driverId']} · clear')),
  ]);
  Widget searchPage() {
    final stops=objects(catalog?['stops']);
    if(stops.isEmpty) return const Text('Start the backend, then refresh. Search uses labelled synthetic timetables; no map API is needed.');
    String stop(int id)=>stops.firstWhere((s)=>s['id']==id)['name'] as String;
    return column([
      card(column([
        Text(mode=='city_bus'?'Городской транспорт':mode=='train'?'Поезда':mode=='intercity_bus'?'Междугородние автобусы':'Сравнение маршрутов',style:Theme.of(context).textTheme.headlineSmall),
        const Text('DEMO · расписание и остановки учебные'),
        ExpansionTile(title:const Text('Примеры направлений'),children:[Wrap(spacing:8,children:[
          TextButton(onPressed:()=>setState((){origin=2;destination=702;mode='train';results=[];selectedRoute=null;}),child:const Text('Актобе → Уральск')),
          TextButton(onPressed:()=>setState((){origin=2;destination=707;mode='All modes';includeUrban=true;results=[];selectedRoute=null;}),child:const Text('Астана: поезд + городской транспорт')),
          TextButton(onPressed:()=>setState((){origin=708;destination=710;mode='All modes';includeUrban=true;results=[];selectedRoute=null;}),child:const Text('Демо метро + трамвай')),
        ])]),
        select<int>('Origin',origin,stops.map((s)=>s['id'] as int).toList(),(v){origin=v;results=[];selectedRoute=null;},display:stop),
        const SizedBox(height:12),
        select<int>('Destination',destination,stops.map((s)=>s['id'] as int).toList(),(v){destination=v;results=[];selectedRoute=null;},display:stop),
        TextField(controller:departure,decoration:InputDecoration(labelText:tr('Departure'),helperText:'YYYY-MM-DD HH:mm · UTC+05'),enabled:!busy,onChanged:(_)=>setState((){results=[];selectedRoute=null;})),
        select<int>('Passengers',passengers,[1,2,3,4],(v)=>passengers=v),
        ExpansionTile(title:Text(tr('Additional parameters')),children:[needControls(),
          select<int>('Transfer buffer',buffer,[15,30],(v)=>buffer=v,display:(v)=>'$v min'),
          select<String>('Mode',mode,['All modes',...((catalog?['availableModes'] as List?)?.cast<String>() ?? ['city_bus','intercity_bus','train','taxi'])],(v){mode=v;results=[];selectedRoute=null;}),
          SwitchListTile(title:const Text('Включить метро / трамвай / LRT'),subtitle:const Text('Только при наличии рейсов в выбранном городе'),value:includeUrban,onChanged:(v)=>setState((){includeUrban=v;results=[];selectedRoute=null;})),
          select<String>('Sort',sort,['fare','duration'],(v)=>sort=v),
        ]),
        button('Find journeys',search,icon:Icons.search),
      ])),
      for(final option in results) card(column([
        Text('${money(option['totalCents'] as num)} · ${(option['durationMinutes'] as num).round()} min',style:Theme.of(context).textTheme.titleLarge),
        Text('${localTime(objects(option['legs']).first['start'] as num)} → ${localTime(objects(option['legs']).last['end'] as num)}'),
        Text('${objects(option['legs']).first['originName']} → ${objects(option['legs']).last['destinationName']}'),
        Text(objects(option['legs']).map((l)=>tr(l['mode'] as String)).join(' → ')),
        button(selectedRoute==option?'Маршрут на карте':'Показать маршрут',()=>setState(()=>selectedRoute=option),icon:Icons.route),
        if(selectedRoute==option) ExpansionTile(title:const Text('Остановки и условия'),children:[itinerary(option,tr)]),
        button('Choose',()=>checkout(option)),
      ])),
    ]);
  }
  Widget profilePage() => card(column([
    if(!signed) ...[
      Text(tr('Sign in'),style:Theme.of(context).textTheme.headlineSmall),
      SwitchListTile(title:Text(tr('Register')),value:registering,onChanged:busy?null:(v)=>setState(()=>registering=v)),
      if(registering) TextField(controller:name,decoration:InputDecoration(labelText:tr('Name')),maxLength:60),
      TextField(controller:email,decoration:InputDecoration(labelText:tr('Email')),keyboardType:TextInputType.emailAddress,autocorrect:false),
      TextField(controller:password,decoration:InputDecoration(labelText:tr('Password'),helperText:'8–128 characters'),obscureText:true,enableSuggestions:false,autocorrect:false,maxLength:128),
      button(registering?'Register':'Sign in',login),
    ] else ...[
      CircleAvatar(radius:32,backgroundColor:avatar=='gold'?Colors.amber:avatar=='blue'?Colors.lightBlue:null,
        child:Text(auth.account!.name.isEmpty?'?':auth.account!.name.substring(0,1))),
      Text('Welcome, ${auth.account!.name}! · ${auth.account!.role}'),Text(auth.account!.login),
      TextField(controller:name,decoration:InputDecoration(labelText:tr('Name')),maxLength:60),
    ],
    const SizedBox(height:16),
    select<String>('Language',locale,['en','ru','kk'],(v){locale=v;remember('locale',v);},display:(v)=>{'en':'English','ru':'Русский','kk':'Қазақша'}[v]!),
    select<String>('Currency',currency,['KZT','USD','EUR'],(v){currency=v;remember('currency',v);}),
    const Text('Fixed demonstration rates: 1 KZT = 0.002 USD / 0.0018 EUR. Checkout is always KZT.'),
    select<String>('Avatar frame',avatar,['plain','blue','gold'],(v){avatar=v;remember('avatar',v);}),
    select<String>('Marker style',marker,['pin','circle','flag'],(v){marker=v;remember('marker',v);}),
    if(signed) ...[
      ExpansionTile(title:Text(tr('Additional parameters')),children:[needControls()]),
      button('Save preferences',()=>saveProfile(false)),
      TextButton(onPressed:busy?null:()=>saveProfile(true),child:Text(tr('Remove preferences'))),
      button('Sign out',()=>run(() async {await auth.logout();results=[];bookings=[];notifications=[];management=null;services=[];drivers=[];parcels=[];need={};}),icon:Icons.logout),
    ],
  ]));
  Future<void> showBooking(Json b) async {
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>BookingDetailPage(auth:auth,booking:b,words:tr)));
  }
  Widget bookingsPage() => column([
    if(pendingCheckout()!=null) button('Resume interrupted checkout',()=>checkout(Map<String,dynamic>.from(pendingCheckout()!['request'] as Map))),
    SwitchListTile(title:Text(tr('History')),value:history,onChanged:(v)=>setState(()=>history=v)),
    for(final b in bookings.where((b)=>history?['completed','cancelled'].contains(b['status']):!['completed','cancelled'].contains(b['status'])))
      card(column([
        Text('${b['id']} · ${b['status']}',style:Theme.of(context).textTheme.titleLarge),
        if(b['disrupted']==1) const Text('⚠ Service change: review your journey'),
        Text(money((b['data'] as Map)['totalCents'] as num)),
        button('Open',()=>showBooking(b)),
      ])),
    if(bookings.isEmpty) Text(tr('No items')),
  ]);
  Widget notificationsPage() => column([
    for(final n in notifications) card(ListTile(
      leading:Icon(n['unread']==1?Icons.mark_email_unread:Icons.mark_email_read),
      title:Text(n['message'] as String),subtitle:Text('${n['booking_id']} · ${localTime(n['at'] as num)}'),
      onTap:()=>run(() async {
        await auth.api('POST','/notifications/read',{'id':n['id']});
        if((n['booking_id'] as String).startsWith('driver:')) {page='Drivers';await reloadPage();return;}
        final b=await auth.api('POST','/booking',{'bookingId':n['booking_id']});
        if(mounted) await showBooking(Map<String,dynamic>.from(b['booking'] as Map));
        await reloadPage();
      }))),
    if(notifications.isEmpty) Text(tr('No items')),
  ]);
  Widget driversPage() => column([
    const Text('История такси и избранные водители',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const Text('DEMO: статусы задаёт администратор. «В сети» не гарантирует свободную машину. Запрос не создаёт бронь.'),
    if(drivers.isEmpty) const Text('После оформления такси здесь появится водитель.'),
    for(final d in drivers) card(column([
      ListTile(leading:Text(d['gender']=='woman'?'👩':'👨',style:const TextStyle(fontSize:32)),
        title:Text('${d['name']} · ${d['vehicle']}'),subtitle:Text('${d['online']==true?"В сети":"Не в сети"} · ${d['capacity']} seats · ${d['rating'] ?? "—"} / 5 (${d['ratingCount']})')),
      Text('Vehicle access: ${d['access']} · pets: ${d['pets']}'),
      TextButton.icon(onPressed:busy?null:()=>run(() async {
        await auth.api('POST','/favourite',{'driverId':d['id'],'saved':d['favourite']!=true});await reloadPage();
      }),icon:Icon(d['favourite']==true?Icons.favorite:Icons.favorite_border),label:Text(d['favourite']==true?'Remove favourite':'Save favourite')),
      button(d['requestStatus']==null?'Запросить этого водителя':'Запрос: ${d['requestStatus']}',()=>run(() async {await auth.api('POST','/taxi/request',{'driverId':d['id']});await reloadPage();}),icon:Icons.notifications_active_outlined),
      if(d['requestStatus']!=null) TextButton(onPressed:()=>run(() async {await auth.api('POST','/taxi/request/cancel',{'driverId':d['id']});await reloadPage();}),child:const Text('Отменить запрос')),
      button('Search',()=>setState(() {need['driverId']=d['id'];page='Search';mode='taxi';results=[];selectedRoute=null;})),
      for(final trip in taxiTrips.where((t)=>t['driverId']==d['id'])) ListTile(
        title:Text('${trip['origin']} → ${trip['destination']}'),subtitle:Text('${localTime(trip['at'] as num)} · ${trip['status']}'),
        onTap:trip['booking']==true?()=>run(() async {final b=await auth.api('POST','/booking',{'bookingId':trip['id']});if(mounted)await showBooking(Map<String,dynamic>.from(b['booking'] as Map));}):null),
    ])),
  ]);
  Future<void> parcelForm() async {
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>ParcelPage(auth:auth,words:tr)));
    if(mounted) await run(reloadPage);
  }
  Widget deliveryPage() => column([
    button('Delivery',parcelForm,icon:Icons.add),
    for(final p in parcels) card(column([
      Text('${p['id']} · ${p['status']}'),Text('${p['data']['origin']} → ${p['data']['destination']}'),
      Text(kzt(p['data']['quote']['totalCents'] as num)),
      if(auth.account?.role=='admin') for(final status in <String,List<String>>{
        'requested':['accepted','rejected'],'accepted':['picked_up','cancelled'],'picked_up':['delivered']
      }[p['status']] ?? <String>[])
        button(status,()=>run(() async {await auth.api('POST','/parcels/advance',{'id':p['id'],'status':status});await reloadPage();})),
    ])),
  ]);
  Future<void> editRecord(String kind,Json data) async {
    final edited=await Navigator.push<Json>(context,MaterialPageRoute(builder:(_)=>RecordEditor(kind:kind,data:data)));
    if(edited==null || !mounted) return;
    await run(() async {
      await auth.api('POST','/manage/$kind',['service','driver','stop'].contains(kind)?{kind:edited}:edited);
      await reloadPage();
    });
  }
  Json newService() => {
    'id':DateTime.now().millisecondsSinceEpoch~/1000,'name':'New demo departure','mode':'city_bus',
    'origin':1,'destination':2,'start':catalog?['demoDeparture'] ?? DateTime.now().millisecondsSinceEpoch/1000+3600,
    'end':(catalog?['demoDeparture'] as num? ?? DateTime.now().millisecondsSinceEpoch/1000+3600)+1800,
    'fareCents':15000,'capacity':10,'operatorId':services.isEmpty?1:services.first['operatorId'],
    'driverId':null,'status':'available','access':{'stepFree':true,'folded':true,'seated':true,'boardingAssistance':true},
    'pets':true,'petSizes':['small','medium'],'carrierRequired':true,
  };
  Widget managementPage() => column([
    const Text('Service-local time is UTC+05. Fares are entered in tiyn (100 tiyn = 1 KZT). All data is simulated.'),
    button('Create service',()=>editRecord('service',newService()),icon:Icons.add),
    ExpansionTile(title:Text('Services (${services.length})'),children:[
      for(final s in services) ListTile(title:Text('${s['id']} · ${s['name']} · ${s['status']}'),
        subtitle:Text('${localTime(s['start'] as num)} · ${kzt(s['fareCents'] as num)} · capacity ${s['capacity']}'),
        trailing:const Icon(Icons.edit),onTap:busy?null:()=>editRecord('service',s)),
    ]),
    if(management!=null) ...[
      ExpansionTile(title:const Text('DEMO: запросы водителям'),children:[
        for(final r in objects(management!['taxiRequests'])) ListTile(title:Text('Водитель #${r['driver_id']} · пассажир #${r['account_id']}'),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${r['status']}'),
          if(['waiting','notified'].contains(r['status'])) Wrap(children:[for(final status in ['accepted','rejected']) TextButton(onPressed:()=>run(() async {await auth.api('POST','/manage/taxi-response',{'driverId':r['driver_id'],'accountId':r['account_id'],'status':status});await reloadPage();}),child:Text(status))]),
        ])),
      ]),
      ExpansionTile(title:const Text('Operators'),children:[
        for(final o in objects(management!['operators'])) ListTile(title:Text('${o['id']} · ${o['name']}'),
          subtitle:Text('Operator account: ${o['account_id'] ?? "unassigned"}'),
          onTap:()=>editRecord('operator',{'id':o['id'],'name':o['name'],'accountId':o['account_id']})),
        button('Add operator',()=>editRecord('operator',{'id':DateTime.now().millisecondsSinceEpoch~/1000,'name':'New operator','accountId':null})),
      ]),
      ExpansionTile(title:const Text('Accounts and roles'),children:[
        for(final a in objects(management!['accounts'])) ListTile(title:Text('${a['id']} · ${a['name']} · ${a['role']}'),
          subtitle:Text(a['email'] as String),onTap:()=>editRecord('account',{'id':a['id'],'role':a['role']})),
      ]),
      ExpansionTile(title:const Text('Drivers and vehicles'),children:[
        for(final d in objects(management!['drivers'])) ListTile(title:Text('${d['name']} · ${d['vehicle']}'),onTap:()=>editRecord('driver',d),trailing:PopupMenuButton<bool>(tooltip:'DEMO: статус в сети',onSelected:(v)=>run(() async {await auth.api('POST','/manage/presence',{'driverId':d['id'],'online':v});await reloadPage();}),itemBuilder:(_)=>[const PopupMenuItem(value:true,child:Text('DEMO: в сети')),const PopupMenuItem(value:false,child:Text('DEMO: не в сети'))])),
        button('Add driver / vehicle',()=>editRecord('driver',{'id':DateTime.now().millisecondsSinceEpoch~/1000,
          'vehicleId':DateTime.now().millisecondsSinceEpoch~/1000,'name':'New driver','gender':'woman','vehicle':'DEMO',
          'capacity':4,'available':true,'access':{},'pets':false,'petSizes':<String>[],'carrierRequired':true})),
      ]),
      ExpansionTile(title:const Text('Stops and transfers'),children:[
        for(final s in objects(management!['stops'])) ListTile(title:Text(s['name'] as String),onTap:()=>editRecord('stop',s)),
      ]),
      button('Find booking by reference',()=>run(() async {
        final ref=await askText(context,'Booking reference');
        if(ref==null)return;
        final data=await auth.api('POST','/booking',{'bookingId':ref.trim().toUpperCase()});
        if(mounted) await showBooking(Map<String,dynamic>.from(data['booking'] as Map));
      })),
      ExpansionTile(title:const Text('Audit history (latest 200)'),children:[
        for(final a in objects(management!['audit'])) ListTile(title:Text(a['event'] as String),subtitle:Text('Actor ${a['actor']} · ${localTime(a['at'] as num)}')),
      ]),
    ],
  ]);
  @override Widget build(BuildContext context) {
    final pages=['Search','Bookings','Notifications','Profile','Drivers','Delivery',if(staff)'Management'];
    if(!pages.contains(page)) page='Profile';
    final content = page!='Search' && page!='Profile' && !signed
      ? column([Text(tr('Sign in')),button('Profile',()=>setState(()=>page='Profile'))])
      : switch(page) {'Search'=>searchPage(),'Profile'=>profilePage(),'Bookings'=>bookingsPage(),
        'Notifications'=>notificationsPage(),'Drivers'=>driversPage(),'Delivery'=>deliveryPage(),_=>managementPage()};
    return Scaffold(appBar:AppBar(title:const Text('interMove 0.8'),actions:[
      IconButton(tooltip:'История такси',onPressed:()=>go('Drivers'),icon:const Icon(Icons.local_taxi_outlined)),
      IconButton(tooltip:'Уведомления ($unread)',onPressed:()=>go('Notifications'),icon:Badge(isLabelVisible:unread>0,label:Text('$unread'),child:const Icon(Icons.notifications_outlined))),
      IconButton(tooltip:tr('Map'),onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.map_outlined)),
      IconButton(tooltip:tr('Refresh'),onPressed:busy?null:load,icon:const Icon(Icons.refresh)),
    ]),body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:double.infinity),
      child:Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:DropdownButton<String>(value:page,isExpanded:true,
          items:pages.map((p)=>DropdownMenuItem(value:p,child:Text(tr(p)))).toList(),onChanged:busy?null:(v){setState(()=>page=v!);run(reloadPage);})),
        Text(tr('DEMO — no real ticket or charge'),textAlign:TextAlign.center),
        if(busy) const LinearProgressIndicator(minHeight:3),
        if(error!=null) Padding(padding:const EdgeInsets.all(12),child:Semantics(liveRegion:true,child:Text(error!,style:const TextStyle(color:Color(0xFF9C1824))))),
        if(!auth.remote) const Padding(padding:EdgeInsets.all(12),child:Text('Для бронирования укажите адрес сервера в настройках главной карты.')),
        Expanded(child:page=='Search'?TransportSplit(map:TransitMap(stops:objects(catalog?['stops']).where((s)=>s['id']==origin || s['id']==destination).toList(),legs:objects(selectedRoute?['legs'])),panel:ListView(padding:const EdgeInsets.all(16),children:[content])):ListView(padding:const EdgeInsets.all(16),children:[content])),
      ])))));
  }
}

Widget compactJourney(Json option) {
  final legs=objects(option['legs']);
  return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    if(legs.isNotEmpty)...[
      Text('${legs.first['originName']} → ${legs.last['destinationName']}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      Text(localTime(legs.first['start'] as num)),
      Text('${legs.length} участок(а) · ${option['durationMinutes'] ?? "—"} мин'),
    ],
    const SizedBox(height:8),Text(kzt(option['totalCents'] as num),style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
  ])));
}

Widget accessSummary(Json leg) {
  String yes(dynamic v)=>v==true?'да':v==false?'нет':'неизвестно';
  final access=Map<String,dynamic>.from(leg['access'] as Map? ?? {});
  final stops=Map<String,dynamic>.from(leg['stopAccess'] as Map? ?? {});
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    for(final e in {'stepFree':'Без ступенек','folded':'Складная коляска','seated':'Оставаться в коляске','boardingAssistance':'Помощь при посадке'}.entries)
      Text('${e.value}: ${yes(access[e.key])}'),
    Text('Без ступенек на посадке: ${yes((stops['origin'] as Map?)?['stepFree'])}'),
    Text('Без ступенек на высадке: ${yes((stops['destination'] as Map?)?['stepFree'])}'),
    Text('С животными: ${yes(leg['pets'])}. Переноска: ${yes(leg['carrierRequired'])}'),
  ]);
}

Widget itinerary(Json option,Words tr) => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  for(final leg in objects(option['legs'])) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${tr(leg['mode'] as String)} · ${leg['operator']} · ${leg['name']}',style:const TextStyle(fontWeight:FontWeight.bold)),
    Text('${leg['originName']} → ${leg['destinationName']}'),
    if(leg['state']!=null) Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
      Icon(leg['state']=='in_progress' || leg['state']=='completed'?Icons.circle_outlined:Icons.directions_bus),
      const Text('→'), Icon(leg['state']=='in_progress'?Icons.directions_bus:Icons.more_horiz),
      const Text('→'), Icon(leg['state']=='completed'?Icons.directions_bus:Icons.location_on_outlined),
      Text('Simulated vehicle: ${leg['state']=='in_progress'?"between stops":leg['state']=='completed'?"destination":"origin"}'),
    ]),
    Text('${localTime(leg['start'] as num)} → ${localTime(leg['end'] as num)}'),
    Text('${kzt(leg['priceCents'] as num)} · ${leg['state'] ?? "available: ${leg['available']}"}'),
    if((leg['waitMinutes'] as num? ?? 0)>0) Text('Transfer waiting time: ${leg['waitMinutes']} min'),
    if(leg['driver']!=null) Text('${leg['driver']['gender']=='woman'?'👩':'👨'} ${leg['driver']['name']} · ${leg['driver']['vehicle']}'),
    if(leg['ticket']!=null) SelectableText('DEMO ticket: ${leg['ticket']}'),
    if((leg['seats'] as List? ?? []).isNotEmpty) Text('Seats: ${(leg['seats'] as List).join(", ")}'),
    ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Access support / animal policy'),children:[
      accessSummary(leg),
    ]),
  ])),

]);

Future<String?> askText(BuildContext context,String title,{String initial=''}) async {
  final controller=TextEditingController(text:initial);
  final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),
    content:TextField(controller:controller,autofocus:true),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),child:const Text('OK'))]));
  controller.dispose();return result;
}

class CheckoutPage extends StatefulWidget {
  final AuthService auth; final Json option; final String? replace; final Words words; final Json? resume;
  const CheckoutPage({super.key,required this.auth,required this.option,required this.words,this.replace,this.resume});
  @override State<CheckoutPage> createState()=>_CheckoutPageState();
}
class _CheckoutPageState extends State<CheckoutPage> {
  late Json option=widget.option;
  late final name=TextEditingController(text:widget.auth.account?.name);
  late final email=TextEditingController(text:widget.auth.account?.login);
  late String key;
  Json? hold, payload;
  String outcome='approved'; String? message;
  bool busy=false, finished=false, paymentSent=false;
  Timer? ticker;
  void savePending() {
    if(payload==null)return;
    widget.auth.local?.saveSetting('pending_checkout',jsonEncode({'accountId':widget.auth.account?.id,
      'backend':widget.auth.endpoint,'request':payload,'hold':hold,'outcome':outcome,'paymentSent':paymentSent}));
  }
  void clearPending() => widget.auth.local?.saveSetting('pending_checkout','');
  @override void initState(){super.initState();
    Json? saved=widget.resume;
    if(saved==null){try{final raw=widget.auth.local?.setting('pending_checkout');
      if(raw!=null && raw.isNotEmpty){final candidate=jsonDecode(raw) as Json;
        if(candidate['accountId']==widget.auth.account?.id && candidate['backend']==widget.auth.endpoint)saved=candidate;}
    }catch(_) {}}
    key=saved?['request']['requestKey'] as String? ?? requestKey();
    if(saved!=null){
      payload=Map<String,dynamic>.from(saved['request'] as Map);option=Map<String,dynamic>.from(payload!);
      if(saved['hold']!=null){hold=Map<String,dynamic>.from(saved['hold'] as Map);option=Map<String,dynamic>.from(hold!['data'] as Map);}
      outcome=saved['outcome'] as String? ?? 'approved';paymentSent=saved['paymentSent']==true;
      name.text=payload!['traveller'] as String;email.text=payload!['email'] as String;
    }
    ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted && hold!=null)setState((){});});}
  @override void dispose(){ticker?.cancel();name.dispose();email.dispose();super.dispose();}
  Future<void> reserve() async {
    if(busy)return;
    if(name.text.trim().isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(()=>message='Enter traveller name and valid contact email.');return;
    }
    setState((){busy=true;message=null;});
    payload ??= {...option,'requestKey':key,'traveller':name.text.trim(),'email':email.text.trim(),'replace':widget.replace};
    try {
      savePending();
      final result=await widget.auth.api('POST','/holds',payload);
      if(!mounted)return;
      setState((){
        if(result['reconfirm']==true) {
          option=Map<String,dynamic>.from(result['quote'] as Map);payload=null;clearPending();
          message='The offer changed. Review the new details, then explicitly reserve again.';
        } else {hold=result;option=Map<String,dynamic>.from(result['data'] as Map);}
      });
      savePending();
    } catch(e){if(mounted)setState(()=>message=failure(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> pay() async {
    if(busy || hold==null)return;
    setState((){busy=true;message=null;});
    try {
      paymentSent=true;savePending();
      final result=await widget.auth.api('POST','/payment',{'holdId':hold!['id'],'outcome':outcome});
      if(!mounted)return;
      clearPending();
      if(result['booking']!=null){Navigator.pop(context,Map<String,dynamic>.from(result['booking'] as Map));return;}
      setState((){finished=true;message='${result['outcome']} · ${result['message'] ?? "No confirmed booking. Capacity released."}';});
    } catch(e){if(mounted)setState(()=>message='${failure(e)} Retry payment to retrieve the same outcome.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> close() async {
    if(busy)return;
    setState(()=>busy=true);
    try {
      if(hold!=null && !finished) await widget.auth.api('POST','/holds/release',{'holdId':hold!['id']});
      clearPending();
      if(mounted)Navigator.pop(context);
    } catch(e){if(mounted)setState(()=>message=failure(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context) {
    final tr=widget.words;
    final remaining=hold==null?0:((hold!['expires'] as num)-DateTime.now().millisecondsSinceEpoch/1000).ceil().clamp(0,300);
    return PopScope(canPop:!busy,child:Scaffold(appBar:AppBar(title:Text(tr('Checkout'))),body:SafeArea(child:TransportSplit(map:TransitMap(stops:const [],legs:objects(option['legs'])),panel:ListView(padding:const EdgeInsets.all(20),children:[
      Text(hold==null?'1. Проверьте поездку':'2. Подтвердите оплату',style:Theme.of(context).textTheme.titleLarge),
      const Text('Демонстрационное бронирование · без списания денег'),
      const SizedBox(height:12),
      compactJourney(option),
      if(widget.replace!=null)Text('Замена ${widget.replace}. Старая бронь действует до успешной оплаты.'),
      const SizedBox(height:12),
      ExpansionTile(title:Text('Пассажир: ${name.text.isEmpty?"укажите данные":name.text}'),
        subtitle:Text('${option['query']['passengers']} чел. · ${email.text}'),initiallyExpanded:name.text.isEmpty || email.text.isEmpty,children:[
        TextField(controller:name,enabled:!busy && payload==null && hold==null,maxLength:60,decoration:InputDecoration(labelText:tr('Lead traveller'))),
        TextField(controller:email,enabled:!busy && payload==null && hold==null,decoration:InputDecoration(labelText:tr('Contact email'))),
      ]),
      ExpansionTile(title:const Text('Маршрут, места и доступность'),children:[itinerary(option,tr)]),
      const Text('До начала поездки: отмена всей брони с возвратом 100% тестовой суммы.'),
      ExpansionTile(title:const Text('Подробные условия отмены'),children:[const Text(
        'После начала первого участка обычная отмена недоступна. При отмене или несовместимом изменении перевозчиком можно подтвердить возврат за незапущенные участки. Частичная добровольная отмена не поддерживается.')]),
      if(hold!=null)Text('Резерв действует ещё ${remaining~/60}:${(remaining%60).toString().padLeft(2,"0")}'),
      if(busy)const LinearProgressIndicator(),
      if(message!=null)Semantics(liveRegion:true,child:Text(message!)),
      if(hold==null)FilledButton(onPressed:busy?null:reserve,child:Text(tr('Reserve for 5 minutes'))),
      if(hold!=null && !finished)...[
        ExpansionTile(title:const Text('Тестовые сценарии оплаты'),subtitle:Text(tr(outcome)),children:[DropdownButton<String>(value:outcome,isExpanded:true,items:['approved','declined','timeout','approved_then_failed']
          .map((s)=>DropdownMenuItem(value:s,child:Text(tr(s)))).toList(),onChanged:busy || paymentSent?null:(v)=>setState(()=>outcome=v!))]),
        FilledButton(onPressed:busy?null:pay,child:Text(tr('Confirm mock payment'))),
      ],
      TextButton(onPressed:busy || (paymentSent && !finished)?null:close,child:Text(tr('Close'))),
    ])))));
  }
}

class BookingDetailPage extends StatefulWidget {
  final AuthService auth; final Json booking; final Words words;
  const BookingDetailPage({super.key,required this.auth,required this.booking,required this.words});
  @override State<BookingDetailPage> createState()=>_BookingDetailPageState();
}
class _BookingDetailPageState extends State<BookingDetailPage> {
  late Json booking=widget.booking;
  bool busy=false;String? error;
  List<Json> alternatives=[];
  Future<void> run(Future<void> Function() action) async {
    if(busy)return;setState((){busy=true;error=null;});
    try{await action();}catch(e){if(mounted)setState(()=>error=failure(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> refresh() async {
    final r=await widget.auth.api('POST','/booking',{'bookingId':booking['id']});
    if(mounted)setState(()=>booking=Map<String,dynamic>.from(r['booking'] as Map));
  }
  Future<void> cancel() => run(() async {
    final quote=await widget.auth.api('POST','/cancellation/quote',{'bookingId':booking['id']});
    if(quote['eligible']!=true)throw FormatException(quote['reason'] as String);
    if(!mounted)return;
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(widget.words('Cancel booking')),
      content:Text('Refund: ${kzt(quote['cents'] as num)}\n${quote['reason']}'),actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(widget.words('Close'))),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(widget.words('Cancel booking')))]));
    if(confirmed!=true)return;
    var reason='Passenger cancellation';
    if(widget.auth.account?.role=='admin' && mounted){
      final entered=await askText(context,'Cancellation reason',initial:'Administrator support');
      if(entered==null)return;reason=entered;
    }
    await widget.auth.api('POST','/cancellation',{'bookingId':booking['id'],'confirmed':true,'expectedCents':quote['cents'],'reason':reason});
    await refresh();
  });
  Future<void> findAlternatives()=>run(() async {
    final r=await widget.auth.api('POST','/alternatives',{'bookingId':booking['id']});
    alternatives=objects(r['options']);
    if(alternatives.isEmpty)throw const FormatException('No compatible alternative found.');
  });
  Future<void> replace(Json option) async {
    final b=await Navigator.push<Json>(context,MaterialPageRoute(builder:(_)=>CheckoutPage(auth:widget.auth,
      option:option,replace:booking['id'] as String,words:widget.words)));
    if(!mounted)return;
    if(b!=null)setState((){booking=b;alternatives=[];});else await run(refresh);
  }
  @override Widget build(BuildContext context) {
    final tr=widget.words;final data=Map<String,dynamic>.from(booking['data'] as Map);
    return Scaffold(appBar:AppBar(title:Text(booking['id'] as String),actions:[IconButton(tooltip:tr('Refresh'),onPressed:busy?null:()=>run(refresh),icon:const Icon(Icons.refresh))]),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(tr('DEMO — no real ticket or charge')),Text('Status: ${booking['status']}'),
        if(booking['disrupted']==1)const Text('⚠ Disruption: review connections and accessibility. No service was substituted.'),
        Text('Traveller: ${data['traveller']} · ${data['email']} · ${data['query']['passengers']} passengers'),
        Text('Paid: ${kzt(data['totalCents'] as num)}'),
        itinerary(data,tr),
        for(final leg in objects(data['legs'])) ...[
          if(leg['current']!=null) Text('Current service: ${leg['current']['status']} · ${localTime(leg['current']['start'] as num)} → ${localTime(leg['current']['end'] as num)}'),
          if(leg['mode']=='taxi' && leg['state']=='completed')Wrap(spacing:4,children:[
            const Text('Rate completed taxi leg:'),
            for(var i=1;i<=5;i++)TextButton(onPressed:busy?null:()=>run(() async {
              await widget.auth.api('POST','/rating',{'bookingId':booking['id'],'legId':leg['id'],'score':i});
              if(mounted)setState(()=>error='Rating saved.');
            }),child:Text('$i ★')),
          ]),
        ],
        for(final refund in objects(booking['refunds']))Text('Refund · leg ${refund['leg_id']}: ${kzt(refund['cents'] as num)}'),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Semantics(liveRegion:true,child:Text(error!)),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton(onPressed:busy?null:cancel,child:Text(tr('Cancel booking'))),
          OutlinedButton(onPressed:busy?null:findAlternatives,child:Text(tr('Replace journey'))),
          TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:const JsonEncoder.withIndent('  ').convert(booking))),child:const Text('Copy demo ticket details')),
          if(widget.auth.account?.role=='admin')FilledButton(onPressed:busy?null:()=>run(() async {
            await widget.auth.api('POST','/manage/advance',{'bookingId':booking['id']});await refresh();
          }),child:const Text('Simulator: advance next leg')),
        ]),
        if(alternatives.isNotEmpty)Text(tr('Alternatives')),
        for(final option in alternatives)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(kzt(option['totalCents'] as num)),itinerary(option,tr),
          FilledButton(onPressed:busy?null:()=>replace(option),child:Text(tr('Replace journey'))),
        ]))),
      ])));
  }
}

class ParcelPage extends StatefulWidget {
  final AuthService auth;final Words words;
  const ParcelPage({super.key,required this.auth,required this.words});
  @override State<ParcelPage> createState()=>_ParcelPageState();
}
class _ParcelPageState extends State<ParcelPage> {
  final fields={for(final k in ['sender','senderContact','recipient','recipientContact','origin','destination','length','width','height','weight']) k:TextEditingController()};
  String size='S', key=requestKey(); bool busy=false; Json? quote,payload;String? error;
  @override void dispose(){for(final c in fields.values){c.dispose();}super.dispose();}
  Future<void> submit(bool confirm) async {
    if(busy)return;setState((){busy=true;error=null;});
    try {
      if(!confirm)payload={
        for(final k in ['sender','senderContact','recipient','recipientContact','origin','destination']) k:fields[k]!.text.trim(),
        'size':size,'dimensions':[for(final k in ['length','width','height'])double.parse(fields[k]!.text)],
        'weight':double.parse(fields['weight']!.text),'requestKey':key,
      };
      final r=await widget.auth.api('POST','/parcels',{...payload!,'confirmed':confirm});
      if(!mounted)return;
      if(confirm){Navigator.pop(context);return;}
      setState(()=>quote=Map<String,dynamic>.from(r['quote'] as Map));
    }catch(e){if(mounted)setState(()=>error=failure(e));}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.words('Delivery'))),body:ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Simulated parcel service. S: 30×20×20 cm / 5 kg; M: 50×40×40 / 10 kg; L: 80×60×60 / 20 kg.'),
    for(final e in fields.entries)TextField(controller:e.value,enabled:!busy && quote==null,
      decoration:InputDecoration(labelText:e.key,helperText:['length','width','height'].contains(e.key)?'cm':e.key=='weight'?'kg':null)),
    DropdownButton<String>(value:size,items:['S','M','L'].map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),
      onChanged:busy || quote!=null?null:(v)=>setState(()=>size=v!)),
    if(error!=null)Semantics(liveRegion:true,child:Text(error!)),if(busy)const LinearProgressIndicator(),
    if(quote==null)FilledButton(onPressed:busy?null:()=>submit(false),child:const Text('Get test quote')),
    if(quote!=null)...[
      Text('Base: ${kzt(quote!['baseCents'] as num)}\nSurcharge: ${kzt(quote!['surchargeCents'] as num)}\nTotal: ${kzt(quote!['totalCents'] as num)}'),
      FilledButton(onPressed:busy?null:()=>submit(true),child:const Text('Confirm demo parcel request')),
      TextButton(onPressed:busy?null:()=>setState((){quote=null;payload=null;key=requestKey();}),child:const Text('Edit')),
    ],
  ]));
}

class RecordEditor extends StatefulWidget {
  final String kind;final Json data;
  const RecordEditor({super.key,required this.kind,required this.data});
  @override State<RecordEditor> createState()=>_RecordEditorState();
}
class _RecordEditorState extends State<RecordEditor> {
  late final Json data=jsonDecode(jsonEncode(widget.data)) as Json;
  final controllers=<String,TextEditingController>{};
  String? error;
  static const integers={'id','operatorId','driverId','vehicleId','capacity','fareCents','accountId','transferMinutes','walkMinutes'};
  static const choices=<String,List<String>>{
    'mode':['city_bus','intercity_bus','train','taxi','metro','tram','lrt'], 'status':['available','delayed','cancelled','unavailable'],
    'gender':['woman','man'],'role':['passenger','operator','admin'],
  };
  @override void initState(){super.initState();for(final e in data.entries){
    if(e.value is Map || e.value is List || e.value is bool || choices.containsKey(e.key) || e.key=='version')continue;
    controllers[e.key]=TextEditingController(text:['start','end'].contains(e.key)?localTime(e.value as num).replaceAll(' UTC+05',''):'${e.value ?? ""}');
  }}
  @override void dispose(){for(final c in controllers.values){c.dispose();}super.dispose();}
  void submit(){
    try{
      for(final e in controllers.entries){
        final text=e.value.text.trim();
        if(['start','end'].contains(e.key)){
          data[e.key]=DateTime.parse('${text.replaceFirst(' ','T')}:00+05:00').millisecondsSinceEpoch/1000;
        }else if(integers.contains(e.key) || ['origin','destination'].contains(e.key)){
          data[e.key]=text.isEmpty && ['driverId','accountId'].contains(e.key)?null:int.parse(text);
        }else if(['lat','lon'].contains(e.key)){data[e.key]=double.parse(text);}
        else{data[e.key]=text;}
      }
      Navigator.pop(context,data);
    }catch(_){setState(()=>error='Check numeric fields and dates (YYYY-MM-DD HH:mm).');}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Edit ${widget.kind}')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Times: UTC+05. Money: integer tiyn (100 = 1 KZT). Stop/operator identifiers are shown in the management catalogue.'),
      for(final e in controllers.entries)TextField(controller:e.value,decoration:InputDecoration(labelText:e.key)),
      for(final e in choices.entries)if(data.containsKey(e.key))DropdownButtonFormField<String>(value:data[e.key] as String,isExpanded:true,
        decoration:InputDecoration(labelText:e.key),items:e.value.map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),
        onChanged:(v)=>setState(()=>data[e.key]=v)),
      for(final key in data.keys.where((k)=>data[k] is bool).toList())SwitchListTile(title:Text(key),value:data[key] as bool,onChanged:(v)=>setState(()=>data[key]=v)),
      if(data['access'] is Map)...[
        const Text('Access: checked = supported; unchecked = unsupported; dash = unknown. Required unknown attributes exclude an option.'),
        for(final key in ['stepFree','folded','seated','boardingAssistance'])CheckboxListTile(title:Text(key),tristate:true,
          value:(data['access'] as Map)[key] as bool?,onChanged:(v)=>setState((){if(v==null){(data['access'] as Map).remove(key);}else{data['access'][key]=v;}})),
      ],
      if(data['petSizes'] is List)for(final size in ['small','medium','large'])CheckboxListTile(title:Text('Pet size: $size'),
        value:(data['petSizes'] as List).contains(size),onChanged:(v)=>setState((){if(v==true){(data['petSizes'] as List).add(size);}else{(data['petSizes'] as List).remove(size);}})),
      if(error!=null)Text(error!),
      FilledButton(onPressed:submit,child:const Text('Save')),
    ]));
}
