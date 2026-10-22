import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'transit_map.dart';

List<Map<String,dynamic>> _rows(dynamic value)=>(value as List? ?? []).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
LatLng _point(Map<String,dynamic> s)=>LatLng((s['lat'] as num).toDouble(),(s['lon'] as num).toDouble());
class UrbanTransportPage extends StatefulWidget {
  final AuthService auth;
  final LatLng? from,to;
  const UrbanTransportPage({super.key,required this.auth,this.from,this.to});
  @override State<UrbanTransportPage> createState()=>_UrbanTransportPageState();
}
class _UrbanTransportPageState extends State<UrbanTransportPage> {
  Map<String,dynamic>? data, line, chosen;
  List<Map<String,dynamic>> options=[];
  LatLng? a,b;
  bool selectA=true,busy=false,tiles=true;
  String? error,notice;
  Map<String,dynamic> needs={};
  @override void initState(){super.initState();a=widget.from;b=widget.to;
    final prefs=widget.auth.account?.preferences ?? <String,dynamic>{};
    needs={for(final k in ['stepFree','boardingAssistance','wheelchair']) if(prefs.containsKey(k))k:prefs[k]};
    load();
  }
  Future<void> run(Future<void> Function() action) async {
    if(busy)return;setState((){busy=true;error=null;});
    try{await action();}catch(e){if(mounted)setState(()=>error=e is FormatException?e.message:'Не удалось загрузить данные. Проверьте сервер в настройках главной карты.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> load()=>run(() async {
    final result=await widget.auth.api('GET','/transit/osm');
    if(!mounted)return;
    setState((){data=result;final lines=_rows(result['lines']);line=lines.isEmpty?null:lines.first;chosen=null;options=[];});
  });
  Future<void> plan()=>run(() async {
    if(a==null || b==null)throw const FormatException('Выберите точки A и B на карте.');
    final result=await widget.auth.api('POST','/transit/osm/plan',{'from':[a!.latitude,a!.longitude],'to':[b!.latitude,b!.longitude],'needs':needs});
    if(mounted)setState((){options=_rows(result['options']);chosen=options.isEmpty?null:options.first;notice=result['message'] as String? ?? result['warning'] as String?;});
  });
  void entireLine(){
    final stops=_rows(line?['stops']);
    if(stops.length<2)return;
    setState((){a=_point(stops.first);b=_point(stops.last);chosen=null;options=[];notice=null;});
  }
  Widget mapView(){
    final legs=_rows(chosen?['legs']);
    final stops=chosen==null?_rows(line?['stops']):[for(final l in legs)..._rows(l['stops'])];
    final polylines=<Polyline>[];
    if(chosen==null){
      for(final segment in line?['shapes'] as List? ?? []){
        final points=(segment as List).map((p)=>LatLng((p[0] as num).toDouble(),(p[1] as num).toDouble())).toList();
        if(points.length>=2)polylines.add(Polyline(points:points,strokeWidth:5,color:Colors.blue));
      }
    }else{
      for(var i=0;i<legs.length;i++)polylines.add(Polyline(points:_rows(legs[i]['stops']).map(_point).toList(),strokeWidth:5,color:i==0?Colors.blue:Colors.purple));
      if(legs.isNotEmpty){
        if(a!=null)polylines.add(Polyline(points:[a!,_point(Map<String,dynamic>.from(legs.first['board'] as Map))],strokeWidth:3,color:Colors.green));
        if(b!=null)polylines.add(Polyline(points:[_point(Map<String,dynamic>.from(legs.last['exit'] as Map)),b!],strokeWidth:3,color:Colors.green));
        if(legs.length==2)polylines.add(Polyline(points:[_point(Map<String,dynamic>.from(legs[0]['exit'] as Map)),_point(Map<String,dynamic>.from(legs[1]['board'] as Map))],strokeWidth:3,color:Colors.green));
      }
    }
    return Stack(children:[FlutterMap(options:MapOptions(initialCenter:a ?? const LatLng(50.2839,57.167),initialZoom:12,
      onTap:(_,p)=>setState((){if(selectA){a=p;selectA=false;}else{b=p;}chosen=null;options=[];notice=null;})),children:[
      if(tiles)TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'kz.intermove.student_prototype'),
      PolylineLayer(polylines:polylines),
      MarkerLayer(markers:[
        for(final s in {for(final s in stops)s['id']:s}.values)Marker(point:_point(s),width:40,height:40,
          child:IconButton(tooltip:s['name'] as String,icon:const Icon(Icons.directions_bus,color:Colors.indigo),onPressed:()=>showModalBottomSheet<void>(context:context,builder:(_)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Text('${s['name']}\n${s['address']}')))))),
        if(a!=null)Marker(point:a!,width:48,height:48,child:const CircleAvatar(backgroundColor:Colors.green,child:Text('A'))),
        if(b!=null)Marker(point:b!,width:48,height:48,child:const CircleAvatar(backgroundColor:Colors.deepOrange,child:Text('B'))),
      ]),
      RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors · ODbL',onTap:()=>launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))]),
    ]),Positioned(left:8,right:8,top:8,child:Card(child:Padding(padding:const EdgeInsets.all(8),child:Wrap(spacing:8,children:[
      Text(chosen==null?'Линия целиком по данным OSM':'Схема выбранных остановок; проходы не проверены'),
      TextButton(onPressed:()=>setState(()=>tiles=!tiles),child:Text(tiles?'Без подложки':'Карта')),
    ]))))]);
  }
  @override Widget build(BuildContext context){
    final lines=_rows(data?['lines']);
    final fetched=(data?['fetchedAt'] as num? ?? 0).toInt();
    final date=DateTime.fromMillisecondsSinceEpoch(fetched*1000).toLocal().toString().split('.').first;
    return Scaffold(appBar:AppBar(title:const Text('Автобусы · OpenStreetMap'),actions:[IconButton(onPressed:busy?null:load,tooltip:'Обновить',icon:const Icon(Icons.refresh))]),
      body:SafeArea(child:TransportSplit(map:mapView(),panel:ListView(padding:const EdgeInsets.all(16),children:[
        const Text('Куда едем?',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
        const Text('Выберите A и B на карте или точки с главной карты.'),
        Wrap(spacing:8,children:[ChoiceChip(label:const Text('Выбрать A'),selected:selectA,onSelected:(_)=>setState(()=>selectA=true)),ChoiceChip(label:const Text('Выбрать B'),selected:!selectA,onSelected:(_)=>setState(()=>selectA=false))]),
        Text('A: ${a==null?"не выбрана":"${a!.latitude.toStringAsFixed(4)}, ${a!.longitude.toStringAsFixed(4)}"}'),
        Text('B: ${b==null?"не выбрана":"${b!.latitude.toStringAsFixed(4)}, ${b!.longitude.toStringAsFixed(4)}"}'),
        if(lines.isNotEmpty)DropdownButtonFormField<int>(value:line?['id'] as int?,isExpanded:true,decoration:const InputDecoration(labelText:'Справочник линий'),
          items:lines.map((l)=>DropdownMenuItem(value:l['id'] as int,child:Text('${l['ref']} · ${l['direction'].toString().isEmpty?l['name']:l['direction']}',maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
          onChanged:busy?null:(v)=>setState((){line=lines.firstWhere((l)=>l['id']==v);chosen=null;options=[];})),
        TextButton(onPressed:busy || line==null?null:entireLine,child:const Text('Поставить A и B по концам линии')),
        ExpansionTile(title:const Text('Требования доступности'),children:[
          SwitchListTile(title:const Text('Без ступенек'),value:needs['stepFree']==true,onChanged:(v)=>setState((){needs['stepFree']=v;options=[];chosen=null;})),
          SwitchListTile(title:const Text('Помощь при посадке'),value:needs['boardingAssistance']==true,onChanged:(v)=>setState((){needs['boardingAssistance']=v;options=[];chosen=null;})),
          DropdownButton<String>(value:needs['wheelchair'] as String? ?? 'none',isExpanded:true,items:['none','folded','seated'].map((v)=>DropdownMenuItem(value:v,child:Text({'none':'Без коляски','folded':'Складная коляска','seated':'Оставаться в коляске'}[v]!))).toList(),onChanged:(v)=>setState((){needs['wheelchair']=v;options=[];chosen=null;})),
        ]),
        FilledButton.icon(onPressed:busy?null:plan,icon:const Icon(Icons.route),label:const Text('Найти схему проезда')),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Semantics(liveRegion:true,child:Text(error!,style:const TextStyle(color:Colors.red))),
        if(notice!=null)Semantics(liveRegion:true,child:Text(notice!)),
        for(final option in options)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(_rows(option['legs']).map((l)=>'№${l['ref']}').join(' → '),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text('Пешком по прямой ≈ ${option['walkMeters']} м · ${_rows(option['legs']).length-1} пересадка'),
          for(final l in _rows(option['legs']))Text('Сесть: ${l['board']['name']}\nВыйти: ${l['exit']['name']}'),
          TextButton(onPressed:()=>setState(()=>chosen=option),child:Text(identical(chosen,option)?'Показано на карте':'Показать на карте')),
        ]))),
        const SizedBox(height:12),
        Text('OSM: ${lines.length} записей направлений. Выгрузка: ${fetched==0?"нет данных":date}'),
        if(data?['warning']!=null)Text(data!['warning'] as String),
        if(data?['stale']==true)const Text('Выгрузка старше суток — актуальность не подтверждена.'),
        const Text('Покрытие неполное. Нет подтверждённого расписания, цен, свободных мест или GPS автобусов. Это справочник, бронирование здесь недоступно.'),
        if(line!=null)ExpansionTile(title:const Text('Остановки выбранной линии'),children:[
          for(final s in _rows(line!['stops']))ListTile(title:Text(s['name'] as String),subtitle:Text(s['address'] as String)),
          TextButton(onPressed:()=>launchUrl(Uri.parse(line!['sourceUrl'] as String)),child:const Text('Открыть источник OSM')),
        ]),
      ]))));
  }
}
