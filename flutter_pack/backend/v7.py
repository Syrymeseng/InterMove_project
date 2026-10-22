"""Versioned demo transport data and account-scoped taxi history/presence."""
import json
import math
import time
from datetime import datetime, timedelta, timezone

SCHEMA = '''
CREATE TABLE IF NOT EXISTS app_migrations(version INTEGER PRIMARY KEY);
CREATE TABLE IF NOT EXISTS driver_presence(driver_id INTEGER PRIMARY KEY, online INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS driver_requests(account_id INTEGER, driver_id INTEGER, status TEXT, at REAL,
 PRIMARY KEY(account_id,driver_id));
CREATE TABLE IF NOT EXISTS demo_rides(id TEXT PRIMARY KEY, account_id INTEGER, driver_id INTEGER,
 request_key TEXT, at REAL, data TEXT, UNIQUE(account_id,request_key));
'''

def seed(db):
    import journeys as j
    if db.execute('SELECT 1 FROM app_migrations WHERE version=7').fetchone(): return
    # Deliberately schematic locations, not verified station entrances or real addresses.
    for identifier,name,city,lat,lon in [
        (701,'DEMO Aktobe bus terminal','Aktobe',50.30,57.17),
        (702,'DEMO Oral rail terminal','Oral',51.23,51.39),
        (703,'DEMO Oral bus terminal','Oral',51.24,51.41),
        (704,'DEMO Oral centre','Oral',51.22,51.37),
        (705,'DEMO Astana rail terminal','Astana',51.20,71.42),
        (706,'DEMO Astana LRT interchange','Astana',51.11,71.44),
        (707,'DEMO Astana destination','Astana',51.09,71.42),
        (708,'DEMO Metro A','Demo City',43.24,76.91),
        (709,'DEMO Metro B / Tram A','Demo City',43.25,76.94),
        (710,'DEMO Tram B','Demo City',43.27,76.96),
    ]:
        if not db.execute('SELECT 1 FROM stops WHERE id=?',(identifier,)).fetchone():
            j.put(db,'stops',dict(id=identifier,name=name,city=city,lat=lat,lon=lon,access=j.ACCESS,
                transferMinutes=15,walkMinutes=0,address='Synthetic stop; verified street address unavailable'))
    for i,name,gender,car,seats,chair,pets in [
        (101,'Алия','woman','Toyota Corolla · DEMO 01',4,False,False),
        (102,'Дана','woman','Hyundai Staria · DEMO 02',3,True,False),
        (103,'Айгерим','woman','Kia Rio · DEMO 03',4,False,True),
        (104,'Арман','man','Hyundai Accent · DEMO 04',4,False,False),
        (105,'Данияр','man','Volkswagen Caddy · DEMO 05',3,True,True),
        (106,'Марат','man','Skoda Octavia · DEMO 06',4,False,True)]:
        j.put(db,'drivers',dict(id=i,name=name,gender=gender,vehicleId=i,vehicle=car,capacity=seats,
            available=i!=106,access={**j.ACCESS,'seated':chair},pets=pets,petSizes=['small','medium'],carrierRequired=True))
    for d in j.records(db,'drivers'):
        db.execute('INSERT OR IGNORE INTO driver_presence VALUES(?,?)',(d['id'],int(d['available'])))
    base=datetime.now(timezone.utc).replace(hour=5,minute=0,second=0,microsecond=0)+timedelta(days=1)
    templates=[('train',2,702,40,520,850000,2,None),('intercity_bus',701,703,20,440,650000,1,None),
        ('city_bus',1,701,0,15,15000,1,None),('city_bus',702,704,550,570,15000,1,None),
        ('city_bus',703,704,470,490,15000,1,None),('taxi',702,704,545,560,175000,3,1),
        ('taxi',1,704,5,400,33000000,3,2),('train',2,705,40,1000,1400000,2,None),
        ('city_bus',705,706,1020,1050,15000,1,None),('lrt',706,707,1070,1085,20000,1,None),
        ('taxi',705,707,1020,1050,350000,3,3),('metro',708,709,10,20,15000,1,None),
        ('tram',709,710,40,55,15000,1,None)]
    sid=max([s['id'] for s in j.records(db,'services')]+[7000])+1
    for day in range(7):
        t=(base+timedelta(days=day)).timestamp()
        for mode,a,b,start,end,fare,operator,driver in templates:
            j.put(db,'services',dict(id=sid,name=f'DEMO {mode} {sid}',mode=mode,origin=a,destination=b,
                start=t+start*60,end=t+end*60,fareCents=fare,capacity=3 if mode=='taxi' else 20,
                operatorId=operator,driverId=driver,access=j.ACCESS,pets=True,petSizes=['small','medium'],
                carrierRequired=True,status='available',version=1,geometryKind='schematic'))
            sid+=1
    db.execute('INSERT INTO app_migrations VALUES(7)')


def taxi_history(db,account):
    import journeys as j
    rows=[]
    for b in db.execute('SELECT * FROM bookings WHERE account_id=? ORDER BY created DESC',(account,)):
        for leg in json.loads(b['data'])['legs']:
            if leg['mode']=='taxi': rows.append(dict(id=b['id'],driverId=leg['driverId'],at=b['created'],
                origin=leg['originName'],destination=leg['destinationName'],status=leg['state'],booking=True))
    for r in db.execute('SELECT * FROM demo_rides WHERE account_id=? ORDER BY at DESC',(account,)):
        rows.append(dict(id=r['id'],driverId=r['driver_id'],at=r['at'],**json.loads(r['data']),status='demo_order',booking=False))
    return sorted(rows,key=lambda x:x['at'],reverse=True)


def presence(db,driver,online,actor,error):
    import journeys as j
    d=j.get(db,'drivers',driver,error)
    if type(online) is not bool: raise error(400,'online must be boolean')
    old=db.execute('SELECT online FROM driver_presence WHERE driver_id=?',(driver,)).fetchone()
    db.execute('INSERT INTO driver_presence VALUES(?,?) ON CONFLICT(driver_id) DO UPDATE SET online=excluded.online',(driver,int(online)))
    if online and (old is None or not old[0]):
        for r in db.execute('SELECT account_id FROM favourites WHERE driver_id=?',(driver,)):
            j.notify(db,r[0],f'driver:{driver}',f'Ваш избранный водитель {d["name"]} в сети! · DEMO')
        for r in db.execute("SELECT account_id FROM driver_requests WHERE driver_id=? AND status='waiting'",(driver,)).fetchall():
            j.notify(db,r[0],f'driver:{driver}',f'{d["name"]}: тестовый запрос получен. Проверьте доступность поездки; машина не забронирована.')
        db.execute("UPDATE driver_requests SET status='notified' WHERE driver_id=? AND status='waiting'",(driver,))
    j.audit(db,actor,f'driver_presence:{driver}:{online}')


def dispatch(db,method,path,data,user,error):
    import journeys as j
    if path=='/taxi/history' and method=='GET':
        trips=taxi_history(db,user['id']); ids={r['driverId'] for r in trips}
        fav={r[0] for r in db.execute('SELECT driver_id FROM favourites WHERE account_id=?',(user['id'],))}
        ds=[]
        for d in j.records(db,'drivers'):
            if d['id'] not in ids|fav: continue
            row=db.execute('SELECT online FROM driver_presence WHERE driver_id=?',(d['id'],)).fetchone()
            req=db.execute('SELECT status FROM driver_requests WHERE account_id=? AND driver_id=?',(user['id'],d['id'])).fetchone()
            ds.append({**d,'online':bool(row and row[0]),'favourite':d['id'] in fav,'requestStatus':req[0] if req else None})
        return {'trips':trips,'drivers':ds,'demo':True}
    if path=='/taxi/request' and method=='POST':
        driver=data.get('driverId'); j.get(db,'drivers',driver,error)
        if driver not in {r['driverId'] for r in taxi_history(db,user['id'])} and not db.execute('SELECT 1 FROM favourites WHERE account_id=? AND driver_id=?',(user['id'],driver)).fetchone():
            raise error(403,'Select a driver from your history or favourites.')
        old=db.execute('SELECT status FROM driver_requests WHERE account_id=? AND driver_id=?',(user['id'],driver)).fetchone()
        if old and old[0] in ('waiting','notified'): return {'status':old[0],'demo':True}
        row=db.execute('SELECT online FROM driver_presence WHERE driver_id=?',(driver,)).fetchone()
        status='notified' if row and row[0] else 'waiting'
        db.execute('INSERT OR REPLACE INTO driver_requests VALUES(?,?,?,?)',(user['id'],driver,status,time.time()))
        j.notify(db,user['id'],f'driver:{driver}','DEMO: запрос конкретному водителю '+('получен симулятором.' if status=='notified' else 'ожидает выхода в сеть.'))
        return {'status':status,'demo':True}
    if path=='/taxi/request/cancel' and method=='POST':
        db.execute('DELETE FROM driver_requests WHERE account_id=? AND driver_id=?',(user['id'],data.get('driverId'))); return {'ok':True}
    if path=='/manage/taxi-requests' and method=='GET':
        j.admin(user,error)
        return {'requests':[dict(r) for r in db.execute('SELECT * FROM driver_requests ORDER BY at DESC')]}
    if path=='/manage/taxi-response' and method=='POST':
        j.admin(user,error)
        status=data.get('status'); account=data.get('accountId'); driver=data.get('driverId')
        if status not in ('accepted','rejected'): raise error(400,'Invalid response.')
        row=db.execute('SELECT status FROM driver_requests WHERE account_id=? AND driver_id=?',(account,driver)).fetchone()
        if row is None: raise error(404,'Request not found.')
        if row[0] in ('accepted','rejected'): return {'status':row[0]}
        db.execute('UPDATE driver_requests SET status=? WHERE account_id=? AND driver_id=?',(status,account,driver))
        j.notify(db,account,f'driver:{driver}',f'DEMO: ответ водителя — {status}. Это не бронирование; выберите подходящую поездку отдельно.')
        j.audit(db,user['id'],f'taxi_request_response:{account}:{driver}:{status}')
        return {'status':status}
    if path=='/manage/presence' and method=='POST':
        j.admin(user,error); presence(db,data.get('driverId'),data.get('online'),user['id'],error);return {'ok':True}
    if path=='/taxi/demo-order' and method=='POST':
        key=data.get('requestKey')
        if not isinstance(key,str) or not 8<=len(key)<=100: raise error(400,'Request key required.')
        old=db.execute('SELECT id FROM demo_rides WHERE account_id=? AND request_key=?',(user['id'],key)).fetchone()
        if old: return {'id':old[0],'demo':True}
        d=j.get(db,'drivers',data.get('driverId'),error)
        for k in ('origin','destination'):
            if not isinstance(data.get(k),str) or not 1<=len(data[k])<=200: raise error(400,'Valid endpoints required.')
        n=data.get('passengers'); meters=data.get('meters')
        if type(n) is not int or not 1<=n<=4 or type(meters) not in (int,float) or not math.isfinite(meters) or not 0<meters<=2000000: raise error(400,'Invalid passengers/distance.')
        if not d['available'] or d['capacity']<n or (data.get('wheelchair') and not d['access'].get('seated')) or (data.get('pets') and not d['pets']): raise error(409,'Driver incompatible.')
        content={k:data[k] for k in ('origin','destination','passengers','meters')};content['fareCents']=round(meters*70)
        identifier='DEMO-'+j.secrets.token_hex(5).upper()
        db.execute('INSERT INTO demo_rides VALUES(?,?,?,?,?,?)',(identifier,user['id'],d['id'],key,time.time(),j.encode(content)))
        j.notify(db,user['id'],f'driver:{d["id"]}',f'DEMO такси оформлено: {data["origin"]} → {data["destination"]}. Водитель: {d["name"]}.')
        j.audit(db,user['id'],'demo_taxi:'+identifier)
        return {'id':identifier,'demo':True}
    raise error(404,'Operation not found.')
