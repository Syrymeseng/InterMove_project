import concurrent.futures
import json
import tempfile
import time
import unittest
from pathlib import Path
from server import Store, ApiError
import journeys

class JourneysTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.store=Store(Path(self.tmp.name)/'db.sqlite')
        self.user=self.store.register({'name':'Passenger','email':'a@example.test','password':'password123'})
        self.other=self.store.register({'name':'Other','email':'b@example.test','password':'password123'})
        self.admin=self.store.register({'name':'Admin','email':'c@example.test','password':'password123'},'admin')
        self.token=self.store.login({'email':'a@example.test','password':'password123'})['token']
        self.other_token=self.store.login({'email':'b@example.test','password':'password123'})['token']
        self.admin_token=self.store.login({'email':'c@example.test','password':'password123'})['token']
        cat=self.api('GET','/catalog',{},'')
        self.q=dict(origin=1,destination=4,passengers=1,departure=cat['demoDeparture'],buffer=15,
                    needs={},modes=list(journeys.MODES),sort='fare')

    def tearDown(self): self.tmp.cleanup()
    def api(self,method,path,data=None,token=None):
        return self.store.dispatch(method,path,data or {},self.token if token is None else token)
    def options(self,q=None): return self.api('POST','/search',q or self.q)['options']
    def hold(self,option=None,key='request-0001',token=None,replace=None):
        option=option or self.options()[0]
        return self.api('POST','/holds',{**option,'requestKey':key,'traveller':'Passenger','email':'a@example.test','replace':replace},token)
    def book(self,option=None,key='request-0001'):
        h=self.hold(option,key)
        return self.api('POST','/payment',{'holdId':h['id'],'outcome':'approved'})['booking']

    def test_multimodal_transfer_no_match_and_sort(self):
        opts=self.options()
        self.assertTrue(any([s['mode'] for s in o['legs']]==['city_bus','train','taxi'] for o in opts))
        self.assertFalse(any(o['ids'][:2]==[1,8] for o in opts))
        self.assertEqual([o['totalCents'] for o in opts],sorted(o['totalCents'] for o in opts))
        self.assertEqual(self.options({**self.q,'origin':1,'destination':5,'needs':{'stepFree':True}}),[])
        self.assertEqual(self.options({**self.q,'needs':{'pets':True,'petType':'dog','petSize':'large','carrier':True}}),[])
        with self.assertRaises(ApiError): self.options({**self.q,'origin':4})
        with self.assertRaises(ApiError): self.options({**self.q,'passengers':5})
        with self.assertRaises(ApiError): self.options({**self.q,'departure':time.time()-1})

    def test_last_seat_race_and_payment_idempotency(self):
        with self.store.connect() as db:
            s=journeys.get(db,'services',5,ApiError); s['capacity']=1; journeys.put(db,'services',s)
        option=next(o for o in self.options() if o['ids']==[5])
        def reserve(args):
            try:return self.hold(option,args[0],args[1])
            except ApiError as e:return e.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(reserve,[('request-one',self.token),('request-two',self.other_token)]))
        self.assertEqual(sum(isinstance(r,dict) and 'id' in r for r in results),1)
        winner=next(i for i,r in enumerate(results) if isinstance(r,dict) and 'id' in r)
        token=[self.token,self.other_token][winner]; hid=results[winner]['id']
        p=self.api('POST','/payment',{'holdId':hid,'outcome':'approved'},token)
        repeat=self.api('POST','/payment',{'holdId':hid,'outcome':'approved'},token)
        self.assertEqual(p['booking']['id'],repeat['booking']['id'])
        self.assertEqual(p['booking']['data']['legs'][0]['seats'],['1'])

    def test_failure_timeout_expiry_and_reversal_release_all(self):
        for i,outcome in enumerate(['declined','timeout','approved_then_failed']):
            h=self.hold(key=f'request-{i:04}')
            result=self.api('POST','/payment',{'holdId':h['id'],'outcome':outcome})
            self.assertNotIn('booking',result)
            with self.store.connect() as db:
                self.assertEqual(db.execute('SELECT count(*) FROM allocations WHERE hold_id=? AND active=1',(h['id'],)).fetchone()[0],0)
        h=self.hold(key='request-expired')
        with self.store.connect() as db:
            db.execute('UPDATE holds SET expires=? WHERE id=?',(time.time()-1,h['id']))
            self.assertEqual(journeys.expire(db),1)
        self.assertEqual(self.api('POST','/payment',{'holdId':h['id'],'outcome':'approved'})['outcome'],'reversed')

    def test_price_reconfirmation_change_at_payment_and_guest_denied(self):
        option=self.options()[0]
        with self.store.connect() as db:
            s=journeys.get(db,'services',option['ids'][0],ApiError); s['fareCents']+=100; s['version']+=1; journeys.put(db,'services',s)
        result=self.hold(option)
        self.assertTrue(result['reconfirm'])
        h=self.hold(result['quote'])
        with self.store.connect() as db:
            s=journeys.get(db,'services',option['ids'][0],ApiError); s['status']='cancelled'; journeys.put(db,'services',s)
        self.assertEqual(self.api('POST','/payment',{'holdId':h['id'],'outcome':'approved'})['outcome'],'reversed')
        with self.assertRaises(ApiError): self.hold(token='')

    def test_booking_privacy_refund_notifications_and_restart(self):
        b=self.book(); ref=b['id']
        with self.assertRaises(ApiError): self.api('POST','/booking',{'bookingId':ref},self.other_token)
        q=self.api('POST','/cancellation/quote',{'bookingId':ref})
        args={'bookingId':ref,'confirmed':True,'expectedCents':q['cents']}
        first=self.api('POST','/cancellation',args)['booking']; second=self.api('POST','/cancellation',args)['booking']
        self.assertEqual(first['refunds'],second['refunds'])
        self.assertEqual(sum(r['cents'] for r in first['refunds']),b['data']['totalCents'])
        reopened=Store(self.store.path)
        self.assertEqual(reopened.dispatch('GET','/bookings',{},self.token)['bookings'][0]['status'],'cancelled')
        self.assertTrue(self.api('GET','/notifications')['notifications'])

    def test_disruption_partial_refund_and_rating(self):
        option=next(o for o in self.options() if len(o['legs'])==3)
        b=self.book(option); ref=b['id']
        for _ in range(2): self.api('POST','/manage/advance',{'bookingId':ref},self.admin_token)
        self.assertFalse(self.api('POST','/cancellation/quote',{'bookingId':ref})['eligible'])
        with self.store.connect() as db:
            s=journeys.get(db,'services',option['ids'][1],ApiError)
        s['status']='cancelled'
        self.api('POST','/manage/service',{'service':s},self.admin_token)
        changed=self.api('POST','/booking',{'bookingId':ref})['booking']
        self.assertTrue(changed['disrupted'])
        q=self.api('POST','/cancellation/quote',{'bookingId':ref})
        self.assertEqual(len(q['legs']),2)
        cancelled=self.api('POST','/cancellation',{'bookingId':ref,'confirmed':True,'expectedCents':q['cents']})['booking']
        self.assertEqual(cancelled['data']['legs'][0]['state'],'completed')
        with self.assertRaises(ApiError): self.api('POST','/rating',{'bookingId':ref,'legId':option['ids'][-1],'score':5})

    def test_replacement_failure_keeps_original_and_success_refunds(self):
        original=self.book(next(o for o in self.options() if o['ids']==[5]))
        alternative=next(o for o in self.options() if o['ids']==[6])
        h=self.hold(alternative,'replacement-one',replace=original['id'])
        self.api('POST','/payment',{'holdId':h['id'],'outcome':'declined'})
        self.assertEqual(self.api('POST','/booking',{'bookingId':original['id']})['booking']['status'],'confirmed')
        h=self.hold(next(o for o in self.options() if o['ids']==[6]),'replacement-two',replace=original['id'])
        self.assertIn('booking',self.api('POST','/payment',{'holdId':h['id'],'outcome':'approved'}))
        self.assertEqual(self.api('POST','/booking',{'bookingId':original['id']})['booking']['status'],'cancelled')

    def test_operator_ownership_and_parcel_limits(self):
        operator=self.store.register({'name':'Op','email':'op@example.test','password':'password123'},'operator')
        token=self.store.login({'email':'op@example.test','password':'password123'})['token']
        self.api('POST','/manage/operator',{'id':1,'name':'City','accountId':operator['id']},self.admin_token)
        with self.store.connect() as db:
            own=journeys.get(db,'services',1,ApiError); other=journeys.get(db,'services',2,ApiError)
        self.api('POST','/manage/service',{'service':own},token)
        with self.assertRaises(ApiError): self.api('POST','/manage/service',{'service':other},token)
        parcel=dict(size='S',dimensions=[30,20,20],weight=5,sender='A',senderContact='a@example.test',recipient='B',recipientContact='b@example.test',origin='One',destination='Two',requestKey='parcel-0001')
        self.assertIn('quote',self.api('POST','/parcels',parcel))
        with self.assertRaises(ApiError): self.api('POST','/parcels',{**parcel,'weight':6})
        sent=self.api('POST','/parcels',{**parcel,'confirmed':True})
        self.assertEqual(sent['id'],self.api('POST','/parcels',{**parcel,'confirmed':True})['id'])


class ExtraIntegrityTests(JourneysTests):
    def test_overlapping_taxi_slots_for_same_vehicle(self):
        option=next(o for o in self.options() if o['ids']==[6])
        self.hold(option)
        with self.store.connect() as db:
            source=journeys.get(db,'services',6,ApiError)
            duplicate={**source,'id':900,'start':source['start']+60,'end':source['end']+60}
            journeys.put(db,'services',duplicate)
        self.assertFalse(any(900 in o['ids'] for o in self.options()))

    def test_unknown_access_change_invalidates_existing_booking(self):
        option=next(o for o in self.options({**self.q,'needs':{'stepFree':True}}) if o['ids']==[5])
        b=self.book(option)
        with self.store.connect() as db:
            stop=journeys.get(db,'stops',4,ApiError)
        stop['access']={}
        self.api('POST','/manage/stop',{'stop':stop},self.admin_token)
        self.assertEqual(self.api('POST','/booking',{'bookingId':b['id']})['booking']['disrupted'],1)

    def test_completed_rating_favourite_notification_read(self):
        option=next(o for o in self.options() if o['ids']==[6]);b=self.book(option)
        for _ in range(2):self.api('POST','/manage/advance',{'bookingId':b['id']},self.admin_token)
        args={'bookingId':b['id'],'legId':6,'score':4}
        self.api('POST','/rating',args)
        with self.assertRaises(ApiError):self.api('POST','/rating',args)
        self.api('POST','/favourite',{'driverId':2,'saved':True})
        d=next(d for d in self.api('GET','/drivers')['drivers'] if d['id']==2)
        self.assertEqual((d['rating'],d['ratingCount'],d['favourite']),(4,1,True))
        note=self.api('GET','/notifications')['notifications'][0]
        self.api('POST','/notifications/read',{'id':note['id']},self.other_token)
        self.assertEqual(self.api('GET','/notifications')['notifications'][0]['unread'],1)
        self.api('POST','/notifications/read',{'id':note['id']})
        self.assertEqual(self.api('GET','/notifications')['notifications'][0]['unread'],0)

for _name in list(JourneysTests.__dict__):
    if _name.startswith('test_') and _name not in ExtraIntegrityTests.__dict__:
        setattr(ExtraIntegrityTests,_name,None)

if __name__=='__main__': unittest.main()
