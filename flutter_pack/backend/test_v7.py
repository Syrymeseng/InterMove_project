import unittest
import json
from server import Store, ApiError
import test_journeys
import journeys

class V7Tests(unittest.TestCase):
    setUp=test_journeys.JourneysTests.setUp
    tearDown=test_journeys.JourneysTests.tearDown
    api=test_journeys.JourneysTests.api
    options=test_journeys.JourneysTests.options
    hold=test_journeys.JourneysTests.hold
    book=test_journeys.JourneysTests.book

    def demo(self,key='demo-order-0001'):
        return self.api('POST','/taxi/demo-order',dict(requestKey=key,driverId=101,origin='A',destination='B',passengers=1,meters=2000))

    def test_demo_history_is_private_and_retry_safe(self):
        self.assertEqual(self.demo(),self.demo())
        history=self.api('GET','/taxi/history')
        self.assertEqual(len(history['trips']),1)
        self.assertEqual(history['drivers'][0]['id'],101)
        self.assertEqual(self.api('GET','/taxi/history',token=self.other_token)['trips'],[])
        with self.assertRaises(ApiError): self.api('POST','/taxi/demo-order',dict(requestKey='invalid-000',driverId=102,origin='A',destination='B',passengers=4,meters=1000))

    def test_only_taxi_legs_enter_history(self):
        self.book(next(o for o in self.options() if o['ids']==[5]))
        self.assertEqual(self.api('GET','/taxi/history')['trips'],[])
        option=next(o for o in self.options() if [l['mode'] for l in o['legs']]==['city_bus','train','taxi'])
        self.book(option,key='multimodal-history')
        self.assertEqual(len(self.api('GET','/taxi/history')['trips']),1)

    def test_favourite_online_transition_and_request(self):
        self.demo()
        self.api('POST','/favourite',{'driverId':101,'saved':True})
        self.api('POST','/manage/presence',{'driverId':101,'online':False},self.admin_token)
        self.assertEqual(self.api('POST','/taxi/request',{'driverId':101})['status'],'waiting')
        before=len(self.api('GET','/notifications')['notifications'])
        self.api('POST','/taxi/request',{'driverId':101})
        self.assertEqual(len(self.api('GET','/notifications')['notifications']),before)
        self.api('POST','/manage/presence',{'driverId':101,'online':True},self.admin_token)
        after=len(self.api('GET','/notifications')['notifications'])
        self.assertEqual(after,before+2)
        self.api('POST','/manage/presence',{'driverId':101,'online':True},self.admin_token)
        self.assertEqual(len(self.api('GET','/notifications')['notifications']),after)
        self.assertEqual(self.api('GET','/taxi/history')['drivers'][0]['requestStatus'],'notified')
        self.api('POST','/favourite',{'driverId':101,'saved':False})
        self.api('POST','/manage/presence',{'driverId':101,'online':False},self.admin_token)
        self.api('POST','/manage/presence',{'driverId':101,'online':True},self.admin_token)
        self.assertEqual(len(self.api('GET','/notifications')['notifications']),after)

    def test_presence_permissions_and_request_isolation(self):
        with self.assertRaises(ApiError): self.api('POST','/manage/presence',{'driverId':101,'online':False})
        with self.assertRaises(ApiError): self.api('POST','/taxi/request',{'driverId':101})
        self.demo();self.api('POST','/taxi/request',{'driverId':101})
        self.api('POST','/taxi/request/cancel',{'driverId':101},self.other_token)
        self.assertIsNotNone(self.api('GET','/taxi/history')['drivers'][0]['requestStatus'])

    def test_driver_response_is_authorized_and_idempotent(self):
        self.demo();self.api('POST','/taxi/request',{'driverId':101})
        with self.store.connect() as db:
            account=db.execute("SELECT id FROM accounts WHERE email='a@example.test'").fetchone()[0]
        payload={'driverId':101,'accountId':account,'status':'accepted'}
        with self.assertRaises(ApiError):self.api('POST','/manage/taxi-response',payload)
        before=len(self.api('GET','/notifications')['notifications'])
        self.api('POST','/manage/taxi-response',payload,self.admin_token)
        self.api('POST','/manage/taxi-response',payload,self.admin_token)
        self.assertEqual(len(self.api('GET','/notifications')['notifications']),before+1)

    def test_additive_upgrade_preserves_v6_booking(self):
        booking=self.book()
        with self.store.connect() as db:
            for table in ('app_migrations','driver_presence','driver_requests','demo_rides'):
                db.execute('DROP TABLE '+table)
            db.execute('DELETE FROM services WHERE id>70')
            db.execute('DELETE FROM stops WHERE id>=701')
            db.execute('DELETE FROM drivers WHERE id>=101')
        self.store=Store(self.store.path)
        self.assertEqual(self.api('POST','/booking',{'bookingId':booking['id']})['booking']['id'],booking['id'])
        self.assertTrue(self.options({**self.q,'origin':2,'destination':702,'modes':['train']}))

    def test_intercity_modes_and_coordinates(self):
        for a,b,mode in [(2,702,'train'),(701,703,'intercity_bus')]:
            opts=self.options({**self.q,'origin':a,'destination':b,'modes':[mode]})
            self.assertTrue(opts)
            self.assertTrue(all(l['mode']==mode for o in opts for l in o['legs']))
            self.assertIn('lat',opts[0]['legs'][0]['destinationStop'])
        self.assertEqual(self.options({**self.q,'origin':1,'destination':4,'modes':['metro']}),[])

    def test_optional_metro_and_astana_alternatives(self):
        opts=self.options({**self.q,'origin':708,'destination':710,'modes':['metro','tram']})
        self.assertTrue(opts)
        self.assertEqual([l['mode'] for l in opts[0]['legs']],['metro','tram'])
        astana=self.options({**self.q,'origin':2,'destination':707,'modes':['train','city_bus','lrt','taxi']})
        modes=[[l['mode'] for l in o['legs']] for o in astana]
        self.assertIn(['train','taxi'],modes)
        self.assertIn(['train','city_bus','lrt'],modes)
        self.book(opts[0])

    def test_restart_does_not_reseed_or_lose_bookings(self):
        booking=self.book();self.demo()
        with self.store.connect() as db: count=db.execute('SELECT count(*) FROM services').fetchone()[0]
        self.store=Store(self.store.path)
        with self.store.connect() as db: self.assertEqual(db.execute('SELECT count(*) FROM services').fetchone()[0],count)
        self.assertEqual(self.api('POST','/booking',{'bookingId':booking['id']})['booking']['id'],booking['id'])
        self.assertTrue(self.api('GET','/taxi/history')['trips'])

if __name__=='__main__':unittest.main()
