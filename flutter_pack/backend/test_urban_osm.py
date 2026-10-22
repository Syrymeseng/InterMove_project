import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import urban_osm as u
from server import Store, ApiError


def stop(id,lon,board=True,exit=True):return dict(id=str(id),name=str(id),lat=0,lon=lon,canBoard=board,canExit=exit)
def line(id,stops):return dict(id=id,ref=str(id),name=str(id),ordered=True,stops=stops)

class UrbanTests(unittest.TestCase):
    def setUp(self):u._memory.clear()
    def test_directed_route_and_no_fictitious_reverse(self):
        c={'lines':[line(1,[stop(1,0),stop(2,.02),stop(3,.04)])]}
        r=u.plan(c,{'from':[0,0],'to':[0,.04]})
        self.assertEqual(len(r['options']),1)
        self.assertEqual(r['options'][0]['legs'][0]['board']['id'],'1')
        self.assertEqual(u.plan(c,{'from':[0,.04],'to':[0,0]})['options'],[])
        self.assertNotIn('departure',r['options'][0])
        self.assertNotIn('fare',r['options'][0])
    def test_single_transfer_and_entry_exit_rules(self):
        c={'lines':[line(1,[stop(1,0),stop(2,.03)]),line(2,[stop(2,.03),stop(3,.06)])]}
        r=u.plan(c,{'from':[0,0],'to':[0,.06]})
        self.assertEqual(len(r['options'][0]['legs']),2)
        c['lines'][0]['stops'][1]['canExit']=False
        self.assertEqual(u.plan(c,{'from':[0,0],'to':[0,.06]})['options'],[])
    def test_access_unknown_does_not_relax_requirements(self):
        c={'lines':[line(1,[stop(1,0),stop(2,.04)])]}
        for needs in ({'stepFree':True},{'wheelchair':'seated'},{'boardingAssistance':True}):
            self.assertEqual(u.plan(c,{'from':[0,0],'to':[0,.04],'needs':needs})['options'],[])
    def test_invalid_coordinates_rejected(self):
        for p in ([float('nan'),0],[100,0],[0,'x'],None):
            with self.assertRaises(ValueError):u.plan({'lines':[]},{'from':p,'to':[0,0]})
    def test_normalize_preserves_order_and_roles(self):
        raw={'elements':[{'type':'node','id':1,'lat':0,'lon':0,'tags':{'name':'One'}},
            {'type':'node','id':2,'lat':0,'lon':.04,'tags':{'name':'Two'}},
            {'type':'relation','id':9,'tags':{'type':'route','route':'bus','public_transport:version':'2'},
             'members':[{'type':'node','ref':1,'role':'stop_entry_only'},{'type':'node','ref':2,'role':'stop_exit_only'}]}]}
        c=u.normalize(raw);l=c['lines'][0]
        self.assertTrue(l['ordered']);self.assertEqual(l['stops'][0]['name'],'One')
        self.assertFalse(l['stops'][0]['canExit']);self.assertFalse(l['stops'][1]['canBoard'])
        del raw['elements'][-1]['tags']['public_transport:version']
        self.assertFalse(u.normalize(raw)['lines'][0]['ordered'])
        with self.assertRaises(ValueError):u.normalize({'remark':'timeout','elements':[]})
    def test_stale_cache_survives_network_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'test.sqlite'
            Path(str(path)+'.osm.json').write_text(json.dumps({'fetchedAt':1,'lines':[]}),encoding='utf-8')
            with patch.object(u,'download',side_effect=OSError('offline')) as fetch:
                result=u.catalogue(path);repeat=u.catalogue(path)
            self.assertTrue(result['stale']);self.assertIsNotNone(result['warning'])
            self.assertEqual(result,repeat);self.assertEqual(fetch.call_count,1)
    def test_real_snapshot_and_public_endpoint_are_read_only(self):
        source=json.loads((Path(__file__).parent/'data'/'aktobe_osm.json').read_text(encoding='utf-8'))
        self.assertEqual(len(source['lines']),3)
        self.assertTrue(all(l['stops'] and l['shapes'] for l in source['lines']))
        with tempfile.TemporaryDirectory() as tmp:
            store=Store(Path(tmp)/'db.sqlite')
            with store.connect() as db:count=db.execute('SELECT count(*) FROM services').fetchone()[0]
            with patch.object(u,'catalogue',return_value=source):
                data=store.dispatch('GET','/transit/osm',{},'')
                self.assertEqual(len(data['lines']),3)
                l=source['lines'][0]
                r=store.dispatch('POST','/transit/osm/plan',{'from':u.point(l['stops'][0]),'to':u.point(l['stops'][-1])},'')
                self.assertTrue(r['options'])
                with self.assertRaises(ApiError):store.dispatch('POST','/transit/osm/plan',{'from':[999,0],'to':[0,0]},'')
            with store.connect() as db:self.assertEqual(db.execute('SELECT count(*) FROM services').fetchone()[0],count)

if __name__=='__main__':unittest.main()
