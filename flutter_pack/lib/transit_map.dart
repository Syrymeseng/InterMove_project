import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keep the selected itinerary visible throughout search and checkout.
class TransportSplit extends StatelessWidget {
  final Widget map, panel;
  const TransportSplit({super.key,required this.map,required this.panel});
  @override Widget build(BuildContext context) => LayoutBuilder(builder:(context,c) {
    if(c.maxWidth>=1000) return Row(children:[Expanded(flex:62,child:map),Expanded(flex:38,child:panel)]);
    return Column(children:[SizedBox(height:(c.maxHeight*.36).clamp(140.0,320.0).toDouble(),child:map),Expanded(child:panel)]);
  });
}
class TransitMap extends StatefulWidget {
  final List<Map<String,dynamic>> stops, legs;
  const TransitMap({super.key,required this.stops,required this.legs});
  @override State<TransitMap> createState()=>_TransitMapState();
}
class _TransitMapState extends State<TransitMap> {
  bool tiles=true;
  Color color(String mode)=>switch(mode){'train'=>Colors.indigo,'taxi'=>Colors.amber.shade800,
    'metro'=>Colors.purple,'tram'=>Colors.deepOrange,'lrt'=>Colors.teal,_=>Colors.blue};
  @override Widget build(BuildContext context) {
    final stops={for(final s in widget.stops) s['id']:s};
    for(final l in widget.legs) {
      for(final key in ['originStop','destinationStop']) {
        if(l[key] is Map) {final s=Map<String,dynamic>.from(l[key] as Map);stops[s['id']]=s;}
      }
    }
    final ids=widget.legs.isEmpty?stops.keys.toSet():{for(final l in widget.legs)...[l['origin'],l['destination']]};
    final shown=ids.where(stops.containsKey).map((id)=>stops[id]!).where((s)=>s['lat'] is num && s['lon'] is num).toList();
    LatLng point(Map<String,dynamic> s)=>LatLng((s['lat'] as num).toDouble(),(s['lon'] as num).toDouble());
    final points=shown.map(point).toList();
    final center=points.isEmpty?const LatLng(50.2839,57.167):LatLng(
      points.map((p)=>p.latitude).reduce((a,b)=>a+b)/points.length,
      points.map((p)=>p.longitude).reduce((a,b)=>a+b)/points.length);
    final span=points.isEmpty?1.0:points.map((p)=>math.max((p.latitude-center.latitude).abs(),(p.longitude-center.longitude).abs())).reduce(math.max);
    final zoom=(8-math.log(math.max(span,.02))/math.ln2).clamp(3.0,13.0).toDouble();
    return Stack(children:[
      FlutterMap(key:ValueKey('${widget.legs.map((l)=>l['id']).join(',')}:${shown.map((s)=>s['id']).join(',')}'),
        options:MapOptions(initialCenter:center,initialZoom:zoom,minZoom:3,maxZoom:19),children:[
          if(tiles) TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'kz.intermove.student_prototype'),
          PolylineLayer(polylines:[for(final l in widget.legs)
            if(stops.containsKey(l['origin']) && stops.containsKey(l['destination']))
              Polyline(points:[point(stops[l['origin']]!),point(stops[l['destination']]!)],strokeWidth:5,color:color(l['mode'] as String)),
          ]),
          MarkerLayer(markers:[for(final s in shown) Marker(point:point(s),width:48,height:48,
            child:Tooltip(message:s['name'] as String,child:IconButton(icon:const Icon(Icons.location_on,size:36,color:Colors.indigo),
              tooltip:s['name'] as String,onPressed:()=>showModalBottomSheet<void>(context:context,builder:(_)=>SafeArea(child:Padding(
                padding:const EdgeInsets.all(24),child:Text('${s['name']}\n${s['address'] ?? "Verified street address unavailable · DEMO"}\n${s['lat']}, ${s['lon']}')))))))]),
          RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors',
            onTap:()=>launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')))]),
        ]),
      Positioned(top:12,left:12,right:12,child:Card(child:Padding(padding:const EdgeInsets.all(8),child:Wrap(
        alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,children:[
          const Text('DEMO · Схема остановок, не точный путь'),
          TextButton(onPressed:()=>setState(()=>tiles=!tiles),child:Text(tiles?'Без подложки':'Показать карту')),
        ])))),
      if(widget.legs.isEmpty) const Positioned(bottom:48,left:12,right:12,child:Card(child:Padding(
        padding:EdgeInsets.all(12),child:Text('Выберите направление и найдите рейсы. Нажмите вариант, чтобы показать его маршрут.')))),
    ]);
  }
}
