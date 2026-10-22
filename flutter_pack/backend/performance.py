"""Isolated synthetic NFR01 benchmark, no changes to the user's demo database."""
import json
import platform
import statistics
import tempfile
import time
from pathlib import Path
from server import Store
import journeys


def fixture(store):
    with store.connect() as db:
        db.execute('DELETE FROM services WHERE id>70');db.execute('DELETE FROM drivers WHERE id>3')
        services=journeys.records(db,'services'); base=min(s['start'] for s in services)
        template=journeys.records(db,'drivers')[0]
        for i in range(4,101):
            journeys.put(db,'drivers',{**template,'id':i,'vehicleId':i,'name':f'Demo driver {i}','vehicle':f'DEMO-{i}'})
        # Exactly 1,000 departures across seven days and all four modes.
        for i in range(len(services)+1,1001):
            sample=dict(services[(i-1)%10]); sample['id']=i; sample['name']=f'Performance departure {i}'
            duration=sample['end']-sample['start']
            sample['start']=base+((i*17)%10000)*60; sample['end']=sample['start']+duration
            if sample['mode']=='taxi':sample['driverId']=(i%100)+1
            journeys.put(db,'services',sample)
        return base-60


def main():
    with tempfile.TemporaryDirectory() as tmp:
        store=Store(Path(tmp)/'fixture.sqlite'); departure=fixture(store)
        elapsed=[]
        for i in range(30):
            q=dict(origin=1,destination=4 if i%3 else 3,departure=departure+(i%7)*86400,
                passengers=(i%4)+1,buffer=15 if i%2 else 30,sort='fare' if i%2 else 'duration',
                needs={} if i%2 else {'stepFree':True},modes=list(journeys.MODES))
            start=time.perf_counter();store.dispatch('POST','/search',q,'');elapsed.append(time.perf_counter()-start)
        report={'environment':platform.platform(),'python':platform.python_version(),'scope':'backend only; not Windows/Android end-to-end',
            'departures':1000,'drivers':100,'searches':30,'within3seconds':sum(t<=3 for t in elapsed),
            'medianSeconds':statistics.median(elapsed),'maxSeconds':max(elapsed),'samplesSeconds':elapsed}
        print(json.dumps(report,indent=2))

if __name__=='__main__':main()
