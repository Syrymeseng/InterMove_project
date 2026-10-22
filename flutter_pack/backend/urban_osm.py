"""Read-only OSM transit catalogue. Never manufactures timetable or sellable capacity."""
import json
import math
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

SOURCE='https://overpass-api.de/api/interpreter'
BACKUP='https://overpass.kumi.systems/api/interpreter'
BBOX='50.18,57.05,50.40,57.40'
QUERY='[out:json][timeout:25];relation["type"="route"]["route"~"^(bus|trolleybus|share_taxi|tram|subway|light_rail)$"]('+BBOX+')->.r;(.r;node(r.r););out body geom;'
MAX_BYTES=12*1024*1024
_LOCK=threading.Lock()
_memory={}

def coord(e):
    if 'lat' in e and 'lon' in e:return [e['lat'],e['lon']]
    g=e.get('geometry',[])
    if g:return [sum(p['lat'] for p in g)/len(g),sum(p['lon'] for p in g)/len(g)]
    return None

def normalize(raw, fetched_at=None):
    if raw.get('remark'):raise ValueError('Overpass returned an incomplete result')
    elements={(e['type'],e['id']):e for e in raw.get('elements',[])}
    lines=[];skipped=0
    for (kind,rid),r in elements.items():
        if kind!='relation' or r.get('tags',{}).get('type')!='route':continue
        tags=r.get('tags',{});members=r.get('members',[])
        stops=[]
        for prefix in ('stop','platform'):
            stops=[]
            for m in members:
                if not m.get('role','').startswith(prefix):continue
                e=elements.get((m['type'],m['ref']),m);p=coord(e)
                if p is None:continue
                key=f"{m['type']}/{m['ref']}"
                if stops and stops[-1]['id']==key:continue
                t=e.get('tags',{});address=' '.join(t[k] for k in ('addr:street','addr:housenumber') if k in t)
                stops.append(dict(id=key,name=t.get('name:ru') or t.get('name') or f'Остановка OSM {m["ref"]}',
                    lat=p[0],lon=p[1],address=address or 'Адрес улицы не указан в OSM',
                    canBoard=not m.get('role','').endswith('exit_only'),canExit=not m.get('role','').endswith('entry_only')))
            if len(stops)>=2:break
        shapes=[]
        for m in members:
            if m['type']!='way' or m.get('role','').startswith(('platform','stop')):continue
            g=elements.get(('way',m['ref']),m).get('geometry',[])
            if len(g)>1:shapes.append([[p['lat'],p['lon']] for p in g])
        ordered=tags.get('public_transport:version')=='2' and len(stops)>=2
        if not ordered:skipped+=1
        lines.append(dict(id=rid,ref=tags.get('ref',''),name=tags.get('name:ru') or tags.get('name') or f'Маршрут {rid}',
            mode=tags.get('route'),direction=tags.get('to',''),origin=tags.get('from',''),operator=tags.get('operator',''),
            stops=stops,shapes=shapes,ordered=ordered,interval=tags.get('interval'),openingHours=tags.get('opening_hours'),
            sourceUrl=f'https://www.openstreetmap.org/relation/{rid}',access='unknown'))
    return dict(source='OpenStreetMap contributors',sourceUrl='https://www.openstreetmap.org/copyright',
        license='ODbL 1.0',fetchedAt=fetched_at or time.time(),osmTimestamp=raw.get('osm3s',{}).get('timestamp_osm_base'),
        bbox=BBOX,lines=lines,unorderedCount=skipped,liveTimetable=False)

def download():
    last=None
    for endpoint in (SOURCE,BACKUP):
        try:
            req=urllib.request.Request(endpoint,data=urllib.parse.urlencode({'data':QUERY}).encode(),headers={'User-Agent':'InterMoveStudentPrototype/0.8'})
            with urllib.request.urlopen(req,timeout=18) as r:blob=r.read(MAX_BYTES+1)
            if len(blob)>MAX_BYTES:raise ValueError('OSM response too large')
            value=normalize(json.loads(blob));value['downloadEndpoint']=endpoint
            return value
        except Exception as e:last=e
    raise last

def catalogue(db_path):
    cache=Path(str(db_path)+'.osm.json');key=str(cache.resolve());now=time.time()
    with _LOCK:
        memo=_memory.get(key)
        if memo and now-memo[0]<300:return memo[1]
        data=None
        for path in (cache,Path(__file__).parent/'data'/'aktobe_osm.json'):
            try:data=json.loads(path.read_text(encoding='utf-8'));break
            except (OSError,ValueError):pass
        warning=None
        if data is None or now-data['fetchedAt']>86400:
            try:
                data=download();cache.parent.mkdir(parents=True,exist_ok=True)
                temp=cache.with_suffix('.tmp');temp.write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8');temp.replace(cache)
            except Exception:
                warning='Обновление OSM недоступно. Показана сохранённая выгрузка.'
        if data is None:data={'lines':[],'fetchedAt':0,'source':'OpenStreetMap contributors','liveTimetable':False}
        result={**data,'stale':now-data.get('fetchedAt',0)>86400,'warning':warning}
        _memory[key]=(now,result)
        return result

def distance(a,b):
    lat1,lon1=map(math.radians,a);lat2,lon2=map(math.radians,b)
    h=math.sin((lat2-lat1)/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 6371000*2*math.asin(min(1,math.sqrt(h)))

def point(s):return [s['lat'],s['lon']]

def plan(catalogue,data):
    def valid(p):return isinstance(p,list) and len(p)==2 and all(type(x) in (int,float) and math.isfinite(x) for x in p) and -90<=p[0]<=90 and -180<=p[1]<=180
    a,b=data.get('from'),data.get('to')
    if not valid(a) or not valid(b):raise ValueError('Выберите две точки на карте.')
    if distance(a,b)<2:raise ValueError('Начало и конец должны различаться.')
    n=data.get('needs',{})
    if not isinstance(n,dict):raise ValueError('Неверные параметры доступности.')
    if n.get('stepFree') or n.get('boardingAssistance') or n.get('wheelchair') in ('folded','seated'):
        return {'options':[],'message':'В OSM недостаточно данных для подтверждения доступности. Обязательные требования сохранены.'}
    lines=[l for l in catalogue['lines'] if l['ordered']]
    options=[]
    def leg(l,i,j):return {'lineId':l['id'],'ref':l['ref'],'name':l['name'],'stops':l['stops'][i:j+1],'board':l['stops'][i],'exit':l['stops'][j]}
    # Directional candidates: do not reverse a route to invent its return service.
    for l in lines:
        ss=l['stops'];best=None
        for i,s in enumerate(ss[:-1]):
            access=distance(a,point(s))
            if access>1200 or not s['canBoard']:continue
            for j in range(i+1,len(ss)):
                exit=distance(point(ss[j]),b)
                if exit>1200 or not ss[j]['canExit']:continue
                candidate={'legs':[leg(l,i,j)],'walkMeters':round(access+exit),'transferMeters':0,'accessMeters':round(access),'exitMeters':round(exit)}
                if best is None or candidate['walkMeters']<best['walkMeters']:best=candidate
        if best:options.append(best)
    # At most one transfer. Walking distances are lower bounds, not verified footpaths.
    for first in lines:
        for second in lines:
            if first['id']==second['id']:continue
            best=None
            for i,s in enumerate(first['stops'][:-1]):
                access=distance(a,point(s))
                if access>1200 or not s['canBoard']:continue
                for k in range(i+1,len(first['stops'])):
                    x=first['stops'][k]
                    if not x['canExit']:continue
                    for m,y in enumerate(second['stops'][:-1]):
                        transfer=distance(point(x),point(y))
                        if transfer>250 or not y['canBoard']:continue
                        for j in range(m+1,len(second['stops'])):
                            z=second['stops'][j];exit=distance(point(z),b)
                            if exit>1200 or not z['canExit']:continue
                            candidate={'legs':[leg(first,i,k),leg(second,m,j)],'walkMeters':round(access+transfer+exit),'transferMeters':round(transfer),'accessMeters':round(access),'exitMeters':round(exit)}
                            if best is None or candidate['walkMeters']<best['walkMeters']:best=candidate
            if best:options.append(best)
    options.sort(key=lambda o:(len(o['legs']),o['walkMeters']))
    return {'options':options[:8],'message':None if options else 'Подходящих связей в доступной выгрузке OSM нет. Это не означает, что автобусов в городе нет.',
        'warning':'Схема проезда без расписания: пересадка по времени не подтверждена. Пешие расстояния по прямой; проверьте проходы.'}

if __name__=='__main__':
    target=Path(__file__).parent/'data'/'aktobe_osm.json';target.parent.mkdir(exist_ok=True)
    value=download();target.write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'lines':len(value['lines']),'stops':sum(len(l['stops']) for l in value['lines']),'fetchedAt':value['fetchedAt']}))
