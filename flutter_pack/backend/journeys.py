"""Seeded transport, atomic reservations and simulated payments (no external carriers)."""
import hashlib
import json
import math
import re
import secrets
import time
from datetime import datetime, timedelta, timezone

SCHEMA = '''
CREATE TABLE IF NOT EXISTS stops(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS operators(id INTEGER PRIMARY KEY, name TEXT NOT NULL, account_id INTEGER UNIQUE);
CREATE TABLE IF NOT EXISTS drivers(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS services(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS holds(id TEXT PRIMARY KEY, account_id INTEGER NOT NULL,
 request_key TEXT NOT NULL, request_hash TEXT NOT NULL, expires REAL NOT NULL,
 status TEXT NOT NULL, data TEXT NOT NULL, UNIQUE(account_id,request_key));
CREATE TABLE IF NOT EXISTS bookings(id TEXT PRIMARY KEY, account_id INTEGER NOT NULL,
 hold_id TEXT UNIQUE NOT NULL, created REAL NOT NULL, status TEXT NOT NULL,
 disrupted INTEGER NOT NULL DEFAULT 0, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS allocations(id INTEGER PRIMARY KEY, hold_id TEXT NOT NULL,
 service_id INTEGER NOT NULL, vehicle_id INTEGER, start REAL, end REAL,
 seat TEXT, qty INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1);
CREATE INDEX IF NOT EXISTS allocation_service ON allocations(service_id,active);
CREATE INDEX IF NOT EXISTS allocation_vehicle ON allocations(vehicle_id,start,end,active);
CREATE TABLE IF NOT EXISTS payments(hold_id TEXT PRIMARY KEY, outcome TEXT NOT NULL, cents INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS refunds(id INTEGER PRIMARY KEY, booking_id TEXT NOT NULL,
 leg_id INTEGER NOT NULL, cents INTEGER NOT NULL, UNIQUE(booking_id,leg_id));
CREATE TABLE IF NOT EXISTS notifications(id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL,
 booking_id TEXT NOT NULL, message TEXT NOT NULL, unread INTEGER NOT NULL DEFAULT 1, at REAL NOT NULL);
CREATE TABLE IF NOT EXISTS favourites(account_id INTEGER,driver_id INTEGER,PRIMARY KEY(account_id,driver_id));
CREATE TABLE IF NOT EXISTS ratings(account_id INTEGER,booking_id TEXT,leg_id INTEGER,driver_id INTEGER,
 score INTEGER CHECK(score BETWEEN 1 AND 5),PRIMARY KEY(booking_id,leg_id));
CREATE TABLE IF NOT EXISTS parcels(id TEXT PRIMARY KEY,account_id INTEGER,request_key TEXT,
 status TEXT,data TEXT,UNIQUE(account_id,request_key));
'''
MODES = ('city_bus', 'intercity_bus', 'train', 'taxi', 'metro', 'tram', 'lrt')
ACCESS = {'stepFree': True, 'folded': True, 'seated': True, 'boardingAssistance': True}

def encode(data):
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

def records(db, table):
    return [json.loads(r['data']) for r in db.execute(f'SELECT data FROM {table}')]

def get(db, table, identifier, error):
    row = db.execute(f'SELECT data FROM {table} WHERE id=?', (identifier,)).fetchone()
    if row is None:
        raise error(404, 'Record not found.')
    return json.loads(row['data'])

def put(db, table, data):
    db.execute(f'INSERT INTO {table}(id,data) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
               (data['id'], encode(data)))

def audit(db, actor, event):
    db.execute('INSERT INTO audit(actor,event,at) VALUES(?,?,?)', (actor, event, time.time()))

def notify(db, account, booking, message):
    db.execute('INSERT INTO notifications(account_id,booking_id,message,at) VALUES(?,?,?,?)',
               (account, booking, message, time.time()))

def seed(db):
    if db.execute('SELECT count(*) FROM stops').fetchone()[0]:
        return
    stops = [(1, 'Aktobe Central', 50.2839, 57.167), (2, 'Aktobe Station', 50.279, 57.207),
             (3, 'Khromtau Station', 50.252, 58.425), (4, 'Khromtau Centre', 50.258, 58.435),
             (5, 'Unknown-access stop', 50.29, 57.18)]
    for identifier, name, lat, lon in stops:
        put(db, 'stops', dict(id=identifier, name=name, lat=lat, lon=lon,
            access=ACCESS if identifier != 5 else {}, transferMinutes=15, walkMinutes=0))
    db.executemany('INSERT INTO operators(id,name) VALUES(?,?)', [(1, 'Demo City Bus'), (2, 'Demo Rail'), (3, 'Demo Taxi')])
    for i, name, gender, seats, access, pets in [
        (1, 'Aliya', 'woman', 4, ACCESS, True), (2, 'Arman', 'man', 4, ACCESS, True),
        (3, 'Dana', 'woman', 3, {**ACCESS, 'seated': False}, False)]:
        put(db, 'drivers', dict(id=i, name=name, gender=gender, vehicleId=i, vehicle=f'DEMO-{i:03}',
            capacity=seats, available=True, access=access, pets=pets, petSizes=['small','medium'],
            carrierRequired=True))
    base = datetime.now(timezone.utc).replace(hour=5, minute=0, second=0, microsecond=0) + timedelta(days=1)
    sid = 0
    for day in range(7):
        t = (base + timedelta(days=day)).timestamp()
        templates = [
            ('city_bus',1,2,0,20,15000,12,1,None,ACCESS,True),
            ('train',2,3,50,170,250000,6,2,None,ACCESS,True),
            ('taxi',3,4,205,220,140000,4,3,1,ACCESS,True),
            ('taxi',3,4,205,225,150000,4,3,2,ACCESS,True),
            ('intercity_bus',1,4,10,210,220000,6,1,None,ACCESS,True),
            ('taxi',1,4,5,170,7000000,4,3,2,ACCESS,True),
            ('city_bus',1,2,5,25,10000,12,1,None,{**ACCESS,'seated':False},False),
            ('train',2,3,27,147,200000,6,2,None,ACCESS,True), # impossible with first bus buffer
            ('city_bus',1,5,0,10,10000,12,1,None,ACCESS,True),
            ('city_bus',1,2,0,20,9000,0,1,None,ACCESS,True),
        ]
        for mode,a,b,start,end,fare,capacity,operator,driver,access,pets in templates:
            sid += 1
            put(db, 'services', dict(id=sid, name=f'DEMO {mode} {sid}', mode=mode, origin=a, destination=b,
                start=t+start*60, end=t+end*60, fareCents=fare, capacity=capacity, operatorId=operator,
                driverId=driver, distanceMeters=round(fare/70) if mode=='taxi' else (4000 if mode=='city_bus' else 100000), access=access, pets=pets, petSizes=['small','medium'], carrierRequired=True,
                status='available', version=1))


def needs(data, error):
    n = data.get('needs', {})
    if not isinstance(n, dict): raise error(400, 'Invalid travel needs.')
    allowed = {'stepFree','boardingAssistance','wheelchair','pets','petType','petSize','carrier','gender','driverId'}
    if set(n)-allowed: raise error(400, 'Unknown travel need.')
    for k in ('stepFree','boardingAssistance','pets','carrier'):
        if k in n and type(n[k]) is not bool: raise error(400, 'Invalid travel need: '+k)
    if n.get('wheelchair','none') not in ('none','folded','seated'): raise error(400, 'Invalid wheelchair option.')
    if n.get('gender','any') not in ('any','woman','man'): raise error(400, 'Invalid driver preference.')
    if n.get('pets'):
        if n.get('petType') not in ('cat','dog','small_pet') or n.get('petSize') not in ('small','medium','large'):
            raise error(400, 'Select pet type and size. Livestock is excluded.')
        n = {**n, 'gender':'any'}
    if 'driverId' in n and (type(n['driverId']) is not int or n['driverId'] < 1):
        raise error(400, 'Invalid favourite driver.')
    return n


def access_ok(attributes, n):
    requested = [k for k in ('stepFree','boardingAssistance') if n.get(k)]
    if n.get('wheelchair','none') != 'none': requested.append(n['wheelchair'])
    return all(attributes.get(k) is True for k in requested)


def pet_ok(record, n):
    return not n.get('pets') or (record.get('pets') is True and n['petSize'] in record.get('petSizes', [])
        and (not record.get('carrierRequired') or n.get('carrier') is True))


def compatible(s, stops, drivers, n):
    if not access_ok(s.get('access', {}), n) or not pet_ok(s, n): return False
    if any(not access_ok(stops[k].get('access',{}), n) for k in (s['origin'],s['destination'])): return False
    if s['mode'] == 'taxi':
        d = drivers.get(s['driverId'])
        if not d or not d['available'] or not access_ok(d.get('access',{}), n) or not pet_ok(d,n): return False
        if n.get('gender','any') != 'any' and d['gender'] != n['gender']: return False
        if n.get('driverId') is not None and d['id'] != n['driverId']: return False
    return True


def expire(db):
    now = time.time()
    expired = [r['id'] for r in db.execute("SELECT id FROM holds WHERE status='held' AND expires<=?", (now,))]
    for hid in expired:
        db.execute("UPDATE holds SET status='expired' WHERE id=?", (hid,))
        db.execute('UPDATE allocations SET active=0 WHERE hold_id=?', (hid,))
    return len(expired)


def capacity(db, s, drivers, ignore=''):
    if s['mode'] == 'taxi':
        d = drivers.get(s['driverId'])
        if d is None or not d['available']: return 0
        occupied = db.execute('SELECT 1 FROM allocations WHERE active=1 AND vehicle_id=? '
            'AND start<? AND end>? AND hold_id!=? LIMIT 1', (d['vehicleId'],s['end'],s['start'],ignore)).fetchone()
        return 0 if occupied else min(s['capacity'], d['capacity'])
    used = db.execute('SELECT coalesce(sum(qty),0) FROM allocations WHERE active=1 AND service_id=? AND hold_id!=?',
                     (s['id'],ignore)).fetchone()[0]
    return max(0, s['capacity']-used)


def query(data, error):
    try:
        origin, dest, count = data['origin'], data['destination'], data['passengers']
        departure = float(data['departure'])
    except (KeyError, TypeError, ValueError): raise error(400, 'Origin, destination, departure and passenger count are required.')
    if type(origin) is not int or type(dest) is not int or origin == dest: raise error(400, 'Choose different endpoints.')
    if type(count) is not int or not 1 <= count <= 4: raise error(400, 'Passenger count must be 1–4.')
    if not math.isfinite(departure) or departure < time.time(): raise error(400, 'Departure must be in the future.')
    buffer = data.get('buffer',15)
    if buffer not in (15,30): raise error(400, 'Transfer time must be 15 or 30 minutes.')
    modes = data.get('modes',list(MODES))
    if not isinstance(modes,list) or not modes or any(m not in MODES for m in modes): raise error(400, 'Invalid mode.')
    sort = data.get('sort','fare')
    if sort not in ('fare','duration'): raise error(400, 'Invalid ordering.')
    return dict(origin=origin,destination=dest,passengers=count,departure=departure,
                buffer=buffer,modes=modes,sort=sort,needs=needs(data,error))


def quote(db, legs, q, stops, drivers):
    operators = {r['id']:r['name'] for r in db.execute('SELECT id,name FROM operators')}
    result = []
    for i,s in enumerate(legs):
        leg = {**s, 'originStop':stops[s['origin']], 'destinationStop':stops[s['destination']], 'originName':stops[s['origin']]['name'], 'destinationName':stops[s['destination']]['name'],
            'operator':operators[s['operatorId']], 'priceCents':s['fareCents']*(1 if s['mode']=='taxi' else q['passengers']),
            'available':capacity(db,s,drivers), 'waitMinutes':0 if i==0 else (s['start']-legs[i-1]['end'])/60,
            'stopAccess':{'origin':stops[s['origin']]['access'],'destination':stops[s['destination']]['access']}}
        if s['mode']=='taxi': leg['driver'] = drivers[s['driverId']]
        result.append(leg)
    fingerprint = hashlib.sha256(encode({'legs':result,'query':q}).encode()).hexdigest()
    return dict(ids=[s['id'] for s in legs], legs=result, totalCents=sum(s['priceCents'] for s in result),
        durationMinutes=(legs[-1]['end']-legs[0]['start'])/60, fingerprint=fingerprint, query=q, demo=True)


def search(db, data, error):
    q = query(data,error)
    stops = {s['id']:s for s in records(db,'stops')}
    drivers = {d['id']:d for d in records(db,'drivers')}
    if q['origin'] not in stops or q['destination'] not in stops: raise error(400, 'Unknown stop.')
    candidates = [s for s in records(db,'services') if s['status'] in ('available','delayed')
        and q['departure'] <= s['start'] <= q['departure']+86400 and s['mode'] in q['modes']
        and capacity(db,s,drivers)>=q['passengers'] and compatible(s,stops,drivers,q['needs'])]
    graph = {}
    for s in candidates: graph.setdefault(s['origin'],[]).append(s)
    found=[]
    def walk(node, path, visited):
        if node == q['destination'] and path:
            found.append(path); return
        if len(path)>=3: return
        for s in graph.get(node,[]):
            if s['destination'] in visited: continue
            if path:
                transfer=stops[node]
                minimum=(max(q['buffer'],transfer['transferMinutes'])+transfer['walkMinutes'])*60
                if s['start'] < path[-1]['end']+minimum: continue
            walk(s['destination'],path+[s],visited|{s['destination']})
    walk(q['origin'],[],{q['origin']})
    def order(path):
        fare=sum(s['fareCents']*(1 if s['mode']=='taxi' else q['passengers']) for s in path)
        duration=path[-1]['end']-path[0]['start']
        return (fare,duration) if q['sort']=='fare' else (duration,fare)
    found.sort(key=order)
    return {'options':[quote(db,path,q,stops,drivers) for path in found[:100]], 'message':None if found else 'No compatible journey. Change your search explicitly; required needs were retained.'}


def itinerary(db, data, error, ignore=''):
    q = query(data['query'],error)
    ids=data.get('ids')
    if not isinstance(ids,list) or not 1<=len(ids)<=3 or any(type(i) is not int for i in ids) or len(set(ids))!=len(ids):
        raise error(400,'Choose one to three unique services.')
    stops={s['id']:s for s in records(db,'stops')}; drivers={s['id']:s for s in records(db,'drivers')}
    legs=[get(db,'services',i,error) for i in ids]
    if legs[0]['origin']!=q['origin'] or legs[-1]['destination']!=q['destination']: raise error(409,'Endpoints changed. Search again.')
    for i,s in enumerate(legs):
        if s['status'] not in ('available','delayed') or s['mode'] not in q['modes'] or s['start']<q['departure']:
            raise error(409,'Service unavailable. Search again.')
        if not compatible(s,stops,drivers,q['needs']) or capacity(db,s,drivers,ignore)<q['passengers']:
            raise error(409,'Capacity or required compatibility is no longer available.')
        if i:
            stop=stops[s['origin']]
            minimum=(max(q['buffer'],stop['transferMinutes'])+stop['walkMinutes'])*60
            if legs[i-1]['destination']!=s['origin'] or s['start']<legs[i-1]['end']+minimum:
                raise error(409,'Transfer is no longer valid.')
    return quote(db,legs,q,stops,drivers)


def owned_booking(db, identifier, user, error):
    row=db.execute('SELECT * FROM bookings WHERE id=?',(identifier,)).fetchone()
    if row is None or (row['account_id']!=user['id'] and user['role']!='admin'): raise error(404,'Booking not found.')
    return row


def booking_view(db,row):
    data=json.loads(row['data'])
    for leg in data['legs']:
        current=db.execute('SELECT data FROM services WHERE id=?',(leg['id'],)).fetchone()
        if current:
            s=json.loads(current['data'])
            leg['current']={k:s[k] for k in ('status','start','end','version')}
    refunds=[dict(r) for r in db.execute('SELECT leg_id,cents FROM refunds WHERE booking_id=?',(row['id'],))]
    return {**dict(row),'data':data,'refunds':refunds,'demo':True}


def effective_start(db, leg):
    row=db.execute('SELECT data FROM services WHERE id=?',(leg['id'],)).fetchone()
    return json.loads(row['data'])['start'] if row else leg['start']

def before_first(db, row):
    content=json.loads(row['data'])
    return all(l['state']=='confirmed' for l in content['legs']) and time.time()<effective_start(db,content['legs'][0])


def cancel_quote(db,row, error):
    data=json.loads(row['data']); now=time.time()
    if row['status'] in ('cancelled','completed'): return {'eligible':False,'reason':'Booking is already '+row['status'],'cents':0,'legs':[]}
    # Simulator states are authoritative for the course demo, even before wall-clock departure.
    before=before_first(db,row)
    if not row['disrupted'] and not before:
        return {'eligible':False,'reason':'The first leg has started. Ordinary cancellation is unavailable.','cents':0,'legs':[]}
    legs=[s for s in data['legs'] if s['state']=='confirmed' and effective_start(db,s)>now]
    if not legs: return {'eligible':False,'reason':'No unstarted legs remain.','cents':0,'legs':[]}
    return {'eligible':True,'reason':'100% simulated refund for eligible unstarted legs.',
            'cents':sum(s['priceCents'] for s in legs),'legs':[s['id'] for s in legs]}


def cancel(db,row,user,error,reason):
    if row['status']=='cancelled': return booking_view(db,row)
    quote=cancel_quote(db,row,error)
    if not quote['eligible']: raise error(409,quote['reason'])
    data=json.loads(row['data'])
    for s in data['legs']:
        if s['id'] not in quote['legs']: continue
        s['state']='cancelled'
        db.execute('INSERT OR IGNORE INTO refunds(booking_id,leg_id,cents) VALUES(?,?,?)',(row['id'],s['id'],s['priceCents']))
        db.execute('UPDATE allocations SET active=0 WHERE hold_id=? AND service_id=?',(row['hold_id'],s['id']))
    status='cancelled' if all(s['state']=='cancelled' for s in data['legs']) else ('in_progress' if any(s['state']=='in_progress' for s in data['legs']) else 'completed')
    data['cancellationReason']=reason
    db.execute('UPDATE bookings SET status=?,data=? WHERE id=?',(status,encode(data),row['id']))
    audit(db,user['id'],f'cancel/refund:{row["id"]}:{quote["cents"]}:{reason}')
    notify(db,row['account_id'],row['id'],'Cancellation and simulated refund recorded.')
    return booking_view(db,db.execute('SELECT * FROM bookings WHERE id=?',(row['id'],)).fetchone())


def hold(db,data,user,error):
    key=data.get('requestKey')
    if not isinstance(key,str) or not 8<=len(key)<=100: raise error(400,'A checkout request key is required.')
    digest=hashlib.sha256(encode(data).encode()).hexdigest()
    previous=db.execute('SELECT * FROM holds WHERE account_id=? AND request_key=?',(user['id'],key)).fetchone()
    if previous:
        if previous['request_hash']!=digest: raise error(409,'Request key was reused with different data.')
        return {**dict(previous),'data':json.loads(previous['data'])}
    fresh=itinerary(db,data,error)
    if data.get('fingerprint')!=fresh['fingerprint']:
        return {'reconfirm':True,'quote':fresh,'message':'Price, schedule, capacity or service details changed. Review and confirm again.'}
    name=data.get('traveller','').strip(); email=data.get('email','').strip()
    if not 1<=len(name)<=60 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email): raise error(400,'Traveller name and contact email are required.')
    replace=data.get('replace')
    if replace:
        old=owned_booking(db,replace,user,error)
        if old['account_id']!=user['id'] or not cancel_quote(db,old,error)['eligible'] or old['status']!='confirmed' or not before_first(db,old):
            raise error(409,'Original booking cannot be replaced.')
    hid=secrets.token_urlsafe(20); deadline=time.time()+300
    fresh.update(traveller=name,email=email,replace=replace,needs=fresh['query']['needs'])
    for s in fresh['legs']:
        count=fresh['query']['passengers']; seats=[]
        if s['mode'] in ('train','intercity_bus'):
            used={r['seat'] for r in db.execute('SELECT seat FROM allocations WHERE active=1 AND service_id=?',(s['id'],))}
            seats=[str(i) for i in range(1,s['capacity']+1) if str(i) not in used][:count]
            if len(seats)!=count: raise error(409,'Seats unavailable.')
        s['seats']=seats; s['state']='pending_payment'
        for seat,qty in ([(seat,1) for seat in seats] if seats else [(None,count)]):
            db.execute('INSERT INTO allocations(hold_id,service_id,vehicle_id,start,end,seat,qty) VALUES(?,?,?,?,?,?,?)',
                (hid,s['id'],s.get('driver',{}).get('vehicleId'),s['start'],s['end'],seat,qty))
    db.execute('INSERT INTO holds VALUES(?,?,?,?,?,?,?)',(hid,user['id'],key,digest,deadline,'held',encode(fresh)))
    return {'id':hid,'expires':deadline,'status':'held','data':fresh}


def pay(db,data,user,error):
    hid=data.get('holdId'); h=db.execute('SELECT * FROM holds WHERE id=? AND account_id=?',(hid,user['id'])).fetchone()
    if h is None: raise error(404,'Hold not found.')
    old=db.execute('SELECT * FROM bookings WHERE hold_id=?',(hid,)).fetchone()
    if old: return {'outcome':'approved','booking':booking_view(db,old)}
    attempt=db.execute('SELECT * FROM payments WHERE hold_id=?',(hid,)).fetchone()
    if attempt: return dict(attempt)
    outcome=data.get('outcome')
    if outcome not in ('approved','declined','timeout','approved_then_failed'): raise error(400,'Select a mock payment outcome.')
    content=json.loads(h['data']); valid=h['status']=='held' and h['expires']>time.time()
    failure=None
    if valid:
        try:
            fresh=itinerary(db,content,error,ignore=hid)
            # Availability changes caused by own hold are ignored; compare actual booked terms.
            for new,oldleg in zip(fresh['legs'],content['legs']):
                if new['version']!=oldleg['version'] or new['priceCents']!=oldleg['priceCents'] or new.get('driver')!=oldleg.get('driver') or new['stopAccess']!=oldleg['stopAccess']:
                    raise error(409,'Service changed while paying; approval reversed. Search again.')
            if content.get('replace'):
                original=owned_booking(db,content['replace'],user,error)
                original_data=json.loads(original['data'])
                if original['status']!='confirmed' or not before_first(db,original):
                    raise error(409,'Original journey has started or changed; replacement cannot proceed.')
        except error as e:
            valid=False; failure=e.message
    if not valid or outcome!='approved':
        result='reversed' if outcome in ('approved','approved_then_failed') else outcome
        db.execute('INSERT INTO payments VALUES(?,?,?)',(hid,result,content['totalCents']))
        db.execute("UPDATE holds SET status='failed' WHERE id=?",(hid,))
        db.execute('UPDATE allocations SET active=0 WHERE hold_id=?',(hid,))
        audit(db,user['id'],f'payment:{hid}:{result}')
        return {'outcome':result,'message':failure or 'No confirmed booking. Holds released.'}
    ref='IM-'+secrets.token_hex(5).upper()
    for leg in content['legs']: leg['state']='confirmed'; leg['ticket']=f'{ref}-{leg["id"]}'
    db.execute('INSERT INTO bookings(id,account_id,hold_id,created,status,data) VALUES(?,?,?,?,?,?)',
        (ref,user['id'],hid,time.time(),'confirmed',encode(content)))
    db.execute('INSERT INTO payments VALUES(?,?,?)',(hid,'approved',content['totalCents']))
    db.execute("UPDATE holds SET status='confirmed' WHERE id=?",(hid,))
    if content.get('replace'):
        cancel(db,original,user,error,'Replaced by '+ref)
    departure=datetime.fromtimestamp(content['legs'][0]['start'],timezone(timedelta(hours=5))).strftime('%Y-%m-%d %H:%M UTC+05')
    notify(db,user['id'],ref,f"Поездка запланирована: {departure}. {content['legs'][0]['originName']} → {content['legs'][-1]['destinationName']}. DEMO: билеты доступны.")
    audit(db,user['id'],'confirmed:'+ref)
    return {'outcome':'approved','booking':booking_view(db,db.execute('SELECT * FROM bookings WHERE id=?',(ref,)).fetchone())}

def recheck(db, actor, reason, service_ids=None, driver_ids=None, stop_ids=None):
    stops={s['id']:s for s in records(db,'stops')}; drivers={s['id']:s for s in records(db,'drivers')}
    services={s['id']:s for s in records(db,'services')}
    for row in db.execute("SELECT * FROM bookings WHERE status IN ('confirmed','in_progress')").fetchall():
        content=json.loads(row['data']); bad=False; changed=False; previous=None
        if service_ids is not None and not any(l['id'] in service_ids for l in content['legs']): continue
        if driver_ids is not None and not any(l.get('driverId') in driver_ids for l in content['legs']): continue
        if stop_ids is not None and not any(l['origin'] in stop_ids or l['destination'] in stop_ids for l in content['legs']): continue
        for booked in content['legs']:
            s=services.get(booked['id'])
            if booked['state'] in ('completed','cancelled'): continue
            if not s: bad=True; continue
            changed |= s['version']!=booked['version'] or (s['mode']=='taxi' and drivers.get(s['driverId'])!=booked.get('driver')) or any(stops[k]['access']!=booked['stopAccess'][side] for k,side in [(s['origin'],'origin'),(s['destination'],'destination')])
            if s['status'] not in ('available','delayed') or not compatible(s,stops,drivers,content['needs']) or s['capacity']<content['query']['passengers'] or (s['mode']=='taxi' and drivers[s['driverId']]['capacity']<content['query']['passengers']): bad=True
            if previous:
                stop=stops[s['origin']]
                if previous['destination']!=s['origin'] or previous['end']+(max(content['query']['buffer'],stop['transferMinutes'])+stop['walkMinutes'])*60>s['start']: bad=True
            previous=s
        if changed or bad:
            db.execute('UPDATE bookings SET disrupted=? WHERE id=?',(int(bad or bool(row['disrupted'])),row['id']))
            notify(db,row['account_id'],row['id'],reason+(' Connection or required access is invalid; cancellation/refund is available.' if bad else ' Review updated service times.'))
    audit(db,actor,reason)


def staff(user,error):
    if user['role'] not in ('operator','admin'): raise error(403,'Operator or administrator access required.')


def admin(user,error):
    if user['role']!='admin': raise error(403,'Administrator access required.')


def operator_access(db, user, operator, error):
    staff(user,error)
    if user['role']=='admin': return
    row=db.execute('SELECT account_id FROM operators WHERE id=?',(operator,)).fetchone()
    if row is None or row['account_id']!=user['id']: raise error(403,'This service belongs to another operator.')


def validate_service(db,s,error):
    for key in ('id','origin','destination','operatorId','capacity','fareCents'):
        if type(s.get(key)) is not int: raise error(400,'Invalid service field: '+key)
    if s['id']<=0 or s['capacity']<0 or s['fareCents']<0 or s['capacity']>1000 or s['fareCents']>100000000:
        raise error(400,'Invalid fare or capacity.')
    if s.get('mode') not in MODES or s.get('status') not in ('available','delayed','cancelled','unavailable'):
        raise error(400,'Invalid service mode/status.')
    if s['origin']==s['destination']: raise error(400,'Endpoints must differ.')
    for key in ('origin','destination'): get(db,'stops',s[key],error)
    if not db.execute('SELECT 1 FROM operators WHERE id=?',(s['operatorId'],)).fetchone(): raise error(400,'Unknown operator.')
    if any(type(s.get(k)) not in (int,float) or not math.isfinite(s[k]) for k in ('start','end')) or s['end']<=s['start']:
        raise error(400,'Invalid departure/arrival time.')
    if not isinstance(s.get('name'),str) or not 1<=len(s['name'])<=100: raise error(400,'Service name required.')
    validate_attributes(s,error)
    if s['mode']=='taxi': get(db,'drivers',s.get('driverId'),error)


def validate_attributes(s,error):
    if not isinstance(s.get('access'),dict) or set(s['access'])-set(ACCESS) or any(type(v) is not bool for v in s['access'].values()):
        raise error(400,'Access values must be booleans; omit unknown values.')
    if type(s.get('pets')) is not bool or type(s.get('carrierRequired')) is not bool:
        raise error(400,'Pet policy required.')
    sizes=s.get('petSizes')
    if not isinstance(sizes,list) or any(v not in ('small','medium','large') for v in sizes): raise error(400,'Invalid pet sizes.')


def manage(db,method,path,data,user,error):
    staff(user,error)
    if method=='GET' and path=='/manage/services':
        allowed={r['id'] for r in db.execute('SELECT id FROM operators WHERE account_id=?',(user['id'],))}
        return {'services':[s for s in records(db,'services') if user['role']=='admin' or s['operatorId'] in allowed]}
    if method=='POST' and path=='/manage/service':
        s=data.get('service')
        if not isinstance(s,dict): raise error(400,'Service object required.')
        validate_service(db,s,error)
        existing=db.execute('SELECT data FROM services WHERE id=?',(s['id'],)).fetchone()
        if existing:
            previous=json.loads(existing['data']); operator_access(db,user,previous['operatorId'],error)
            # Booked endpoints/mode/vehicle are immutable; create another service instead.
            booked=db.execute('SELECT 1 FROM allocations WHERE service_id=?',(s['id'],)).fetchone()
            if booked and any(s.get(k)!=previous.get(k) for k in ('origin','destination','mode','driverId')):
                raise error(409,'Create a new service to change booked endpoints/mode/driver.')
            version=previous['version']+1
        else: version=1
        operator_access(db,user,s['operatorId'],error)
        used=db.execute('SELECT coalesce(sum(qty),0) FROM allocations WHERE service_id=? AND active=1',(s['id'],)).fetchone()[0]
        if s['capacity']<used: raise error(409,'Capacity cannot be lower than active reservations. Cancel/disrupt the service first.')
        s={**s,'version':version}; put(db,'services',s)
        recheck(db,user['id'],f'Service {s["id"]} updated.',service_ids={s['id']})
        return {'service':s}
    if path=='/manage/catalog' and method=='GET':
        admin(user,error)
        return {'operators':[dict(r) for r in db.execute('SELECT * FROM operators')], 'drivers':records(db,'drivers'),
            'stops':records(db,'stops'), 'accounts':[dict(r) for r in db.execute('SELECT id,name,email,role FROM accounts')],
            'audit':[dict(r) for r in db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 200')]}
    if path=='/manage/operator' and method=='POST':
        admin(user,error)
        identifier=data.get('id'); name=data.get('name'); account=data.get('accountId')
        if type(identifier) is not int or identifier<=0 or not isinstance(name,str) or not 1<=len(name)<=100: raise error(400,'Invalid operator.')
        if account is not None and not db.execute("SELECT 1 FROM accounts WHERE id=? AND role='operator'",(account,)).fetchone(): raise error(400,'Assign an operator account.')
        db.execute('INSERT INTO operators(id,name,account_id) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,account_id=excluded.account_id',(identifier,name,account))
        audit(db,user['id'],'operator_updated:'+str(identifier)); return {'ok':True}
    if path=='/manage/account' and method=='POST':
        admin(user,error)
        identifier=data.get('id'); role=data.get('role')
        if role not in ('passenger','operator','admin') or type(identifier) is not int: raise error(400,'Invalid account/role.')
        if identifier==user['id']: raise error(409,'Cannot change your own administrator role.')
        if not db.execute('SELECT 1 FROM accounts WHERE id=?',(identifier,)).fetchone(): raise error(404,'Account not found.')
        if role!='operator': db.execute('UPDATE operators SET account_id=NULL WHERE account_id=?',(identifier,))
        db.execute('UPDATE accounts SET role=? WHERE id=?',(role,identifier))
        db.execute('DELETE FROM sessions WHERE account_id=?',(identifier,))
        audit(db,user['id'],f'account_role:{identifier}:{role}'); return {'ok':True}
    if path=='/manage/driver' and method=='POST':
        admin(user,error); d=data.get('driver')
        if not isinstance(d,dict): raise error(400,'Driver object required.')
        for key in ('id','vehicleId','capacity'):
            if type(d.get(key)) is not int or d[key]<1: raise error(400,'Invalid driver/vehicle/capacity.')
        if d['capacity']>20 or d.get('gender') not in ('woman','man') or type(d.get('available')) is not bool: raise error(400,'Invalid driver attributes.')
        if any(not isinstance(d.get(k),str) or not 1<=len(d[k])<=100 for k in ('name','vehicle')): raise error(400,'Driver name and vehicle are required.')
        validate_attributes(d,error)
        old=db.execute('SELECT data FROM drivers WHERE id=?',(d['id'],)).fetchone()
        if old and json.loads(old['data'])['vehicleId']!=d['vehicleId']:
            raise error(409,'Create a new driver record for a different vehicle in this prototype.')
        put(db,'drivers',d); recheck(db,user['id'],'Driver/vehicle attributes changed.',driver_ids={d['id']}); return {'driver':d}
    if path=='/manage/stop' and method=='POST':
        admin(user,error); s=data.get('stop')
        if not isinstance(s,dict) or type(s.get('id')) is not int or not isinstance(s.get('name'),str): raise error(400,'Invalid stop.')
        if not isinstance(s.get('access'),dict) or set(s['access'])-set(ACCESS) or any(type(v) is not bool for v in s['access'].values()): raise error(400,'Invalid access attributes.')
        for k in ('transferMinutes','walkMinutes'):
            if type(s.get(k)) is not int or not 0<=s[k]<=180: raise error(400,'Invalid transfer time.')
        if any(type(s.get(k)) not in (int,float) or not math.isfinite(s[k]) for k in ('lat','lon')) or abs(s['lat'])>90 or abs(s['lon'])>180: raise error(400,'Invalid coordinates.')
        put(db,'stops',s); recheck(db,user['id'],'Stop/transfer attributes changed.',stop_ids={s['id']}); return {'stop':s}
    if path=='/manage/advance' and method=='POST':
        admin(user,error)
        row=owned_booking(db,data.get('bookingId'),user,error); content=json.loads(row['data'])
        if row['status'] not in ('confirmed','in_progress'): raise error(409,'Cannot advance this booking.')
        for s in content['legs']:
            if s['state']=='in_progress': s['state']='completed'; break
            if s['state']=='confirmed': s['state']='in_progress'; break
        status='completed' if all(s['state'] in ('completed','cancelled') for s in content['legs']) else 'in_progress'
        db.execute('UPDATE bookings SET status=?,data=? WHERE id=?',(status,encode(content),row['id']))
        audit(db,user['id'],'simulator_advance:'+row['id']); notify(db,row['account_id'],row['id'],'Simulated journey status updated.')
        return booking_view(db,db.execute('SELECT * FROM bookings WHERE id=?',(row['id'],)).fetchone())
    raise error(404,'Management operation not found.')


def extras(db,method,path,data,user,error):
    if path=='/drivers' and method=='GET':
        favourites={r[0] for r in db.execute('SELECT driver_id FROM favourites WHERE account_id=?',(user['id'],))}
        result=[]
        for d in records(db,'drivers'):
            r=db.execute('SELECT avg(score),count(*) FROM ratings WHERE driver_id=?',(d['id'],)).fetchone()
            result.append({**d,'favourite':d['id'] in favourites,'rating':r[0],'ratingCount':r[1]})
        return {'drivers':result}
    if path=='/favourite' and method=='POST':
        d=get(db,'drivers',data.get('driverId'),error)
        if type(data.get('saved')) is not bool: raise error(400,'saved must be boolean.')
        if data['saved']: db.execute('INSERT OR IGNORE INTO favourites VALUES(?,?)',(user['id'],d['id']))
        else: db.execute('DELETE FROM favourites WHERE account_id=? AND driver_id=?',(user['id'],d['id']))
        return {'ok':True}
    if path=='/rating' and method=='POST':
        row=owned_booking(db,data.get('bookingId'),user,error)
        if row['account_id']!=user['id']: raise error(403,'Only the booking passenger can rate.')
        leg=next((s for s in json.loads(row['data'])['legs'] if s['id']==data.get('legId')),None)
        if not leg or leg['mode']!='taxi' or leg['state']!='completed': raise error(409,'Rate a completed taxi leg only.')
        score=data.get('score')
        if type(score) is not int or not 1<=score<=5: raise error(400,'Rating must be 1–5.')
        if db.execute('SELECT 1 FROM ratings WHERE booking_id=? AND leg_id=?',(row['id'],leg['id'])).fetchone(): raise error(409,'This taxi leg already has a rating.')
        db.execute('INSERT INTO ratings VALUES(?,?,?,?,?)',(user['id'],row['id'],leg['id'],leg['driverId'],score)); return {'ok':True}
    if path=='/parcels' and method=='GET':
        rows=db.execute('SELECT * FROM parcels'+('' if user['role']=='admin' else ' WHERE account_id=?'),() if user['role']=='admin' else (user['id'],)).fetchall()
        return {'parcels':[{**dict(r),'data':json.loads(r['data'])} for r in rows]}
    if path=='/parcels' and method=='POST':
        limits={'S':([30,20,20],5,100000),'M':([50,40,40],10,150000),'L':([80,60,60],20,200000)}
        size=data.get('size'); dims=data.get('dimensions'); weight=data.get('weight')
        if size not in limits or not isinstance(dims,list) or len(dims)!=3 or any(type(v) not in (float,int) or not math.isfinite(v) or v<=0 for v in dims) or type(weight) not in (int,float) or not math.isfinite(weight) or weight<=0: raise error(400,'Valid size, three dimensions and weight are required.')
        bounds,max_weight,base=limits[size]
        if weight>max_weight or any(v>limit for v,limit in zip(sorted(dims,reverse=True),sorted(bounds,reverse=True))): raise error(400,'Parcel exceeds the chosen size/weight limit.')
        for key in ('sender','senderContact','recipient','recipientContact','origin','destination'):
            if not isinstance(data.get(key),str) or not 1<=len(data[key].strip())<=200: raise error(400,'Required parcel field: '+key)
        if data['origin'].strip()==data['destination'].strip(): raise error(400,'Parcel endpoints must differ.')
        key=data.get('requestKey')
        if not isinstance(key,str) or not 8<=len(key)<=100: raise error(400,'Request key required.')
        existing=db.execute('SELECT * FROM parcels WHERE account_id=? AND request_key=?',(user['id'],key)).fetchone()
        if existing: return {**dict(existing),'data':json.loads(existing['data'])}
        if data.get('confirmed') is not True: return {'quote':{'baseCents':base,'surchargeCents':0,'totalCents':base,'demo':True}}
        identifier='PAR-'+secrets.token_hex(5).upper(); content={**data,'quote':{'baseCents':base,'surchargeCents':0,'totalCents':base},'demo':True}
        db.execute('INSERT INTO parcels VALUES(?,?,?,?,?)',(identifier,user['id'],key,'requested',encode(content)))
        audit(db,user['id'],'parcel_requested:'+identifier)
        return {'id':identifier,'status':'requested','data':content}
    if path=='/parcels/advance' and method=='POST':
        admin(user,error); row=db.execute('SELECT * FROM parcels WHERE id=?',(data.get('id'),)).fetchone()
        if row is None: raise error(404,'Parcel not found.')
        transitions={'requested':['accepted','rejected'],'accepted':['picked_up','cancelled'],'picked_up':['delivered']}
        status=data.get('status')
        if status not in transitions.get(row['status'],[]): raise error(409,'Invalid delivery status transition.')
        db.execute('UPDATE parcels SET status=? WHERE id=?',(status,row['id']))
        audit(db,user['id'],f'parcel_status:{row["id"]}:{status}'); return {'ok':True}
    raise error(404,'Operation not found.')


def dispatch(db,method,path,data,user,error):
    expire(db)
    if path=='/catalog' and method=='GET':
        services=records(db,'services'); future=[s['start'] for s in services if s['start']>time.time()]
        return {'stops':records(db,'stops'),'operators':[dict(r) for r in db.execute('SELECT id,name FROM operators')],
            'demoDeparture':min(future)-60 if future else time.time()+3600,
            'availableModes':sorted({s['mode'] for s in services}), 'currency':'KZT','displayRates':{'KZT':1,'USD':0.002,'EUR':0.0018},
            'timeZone':'UTC+05:00','demo':True}
    if path=='/search' and method=='POST': return search(db,data,error)
    if user is None: raise error(401,'Sign in before booking.')
    if path=='/holds' and method=='POST': return hold(db,data,user,error)
    if path=='/holds/release' and method=='POST':
        h=db.execute('SELECT * FROM holds WHERE id=? AND account_id=?',(data.get('holdId'),user['id'])).fetchone()
        if h and h['status']=='held':
            db.execute("UPDATE holds SET status='cancelled' WHERE id=?",(h['id'],)); db.execute('UPDATE allocations SET active=0 WHERE hold_id=?',(h['id'],))
        return {'ok':True}
    if path=='/payment' and method=='POST': return pay(db,data,user,error)
    if path=='/bookings' and method=='GET':
        return {'bookings':[booking_view(db,r) for r in db.execute('SELECT * FROM bookings WHERE account_id=? ORDER BY created DESC',(user['id'],))]}
    if path in ('/booking','/cancellation/quote','/cancellation','/alternatives') and method=='POST':
        row=owned_booking(db,data.get('bookingId'),user,error)
        if path=='/booking': return {'booking':booking_view(db,row)}
        if path=='/cancellation/quote': return cancel_quote(db,row,error)
        if path=='/cancellation':
            if data.get('confirmed') is not True: raise error(400,'Explicit cancellation confirmation required.')
            current=cancel_quote(db,row,error)
            if row['status']!='cancelled' and data.get('expectedCents')!=current['cents']: raise error(409,'Refund amount changed. Review again.')
            reason=data.get('reason','Passenger cancellation')
            if not isinstance(reason,str) or not 1<=len(reason)<=200: raise error(400,'Cancellation reason required.')
            return {'booking':cancel(db,row,user,error,reason)}
        content=json.loads(row['data']); q={**content['query'],'departure':max(time.time()+5,content['query']['departure'])}
        return search(db,q,error)
    if path=='/notifications' and method=='GET':
        return {'notifications':[dict(r) for r in db.execute('SELECT * FROM notifications WHERE account_id=? ORDER BY id DESC',(user['id'],))]}
    if path=='/notifications/read' and method=='POST':
        db.execute('UPDATE notifications SET unread=0 WHERE id=? AND account_id=?',(data.get('id'),user['id'])); return {'ok':True}
    if path.startswith('/taxi/') or path in ('/manage/presence','/manage/taxi-requests','/manage/taxi-response'):
        import v7
        return v7.dispatch(db,method,path,data,user,error)
    if path.startswith('/manage/'): return manage(db,method,path,data,user,error)
    return extras(db,method,path,data,user,error)
