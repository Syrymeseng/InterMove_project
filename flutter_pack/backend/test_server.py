import concurrent.futures
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from server import Store, make_server


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'test.sqlite'
        self.server = make_server(self.path, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'
        self.data = {'name': 'Demo Passenger', 'email': 'demo@example.test', 'password': 'Test-pass-123'}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def call(self, method, path, data=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer '+token
        request = urllib.request.Request(self.base+path,
            data=json.dumps(data).encode() if data is not None else None,
            headers=headers, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as e:
            response = e
        with response:
            return response.status, json.load(response)

    def login(self, data=None):
        status, result = self.call('POST', '/auth/login', data or self.data)
        self.assertEqual(status, 200)
        return result['token']

    def test_registration_validation_duplicate_and_no_role_escalation(self):
        status, body = self.call('POST', '/auth/register', {**self.data, 'role': 'admin'})
        self.assertEqual(status, 200)
        self.assertEqual(body['account']['role'], 'passenger')
        self.assertEqual(self.call('POST', '/auth/register', {**self.data, 'email': 'DEMO@example.test'})[0], 409)
        status, body = self.call('POST', '/auth/register', {**self.data, 'email': 'broken'})
        self.assertEqual((status, body['field']), (400, 'email'))
        token = self.login()
        self.assertEqual(self.call('GET', '/admin/summary', token=token)[0], 403)
        self.assertEqual(self.call('GET', '/me')[0], 401)

    def test_sessions_profile_ownership_persistence_and_logout(self):
        self.call('POST', '/auth/register', self.data)
        token = self.login()
        second_device = self.login()
        prefs = {'wheelchair': 'seated', 'stepFree': True, 'boardingAssistance': True}
        status, body = self.call('PATCH', '/me', {'name': 'New name', 'preferences': prefs,
            'id': 999, 'role': 'admin'}, token)
        self.assertEqual(status, 200)
        self.assertEqual(body['account']['role'], 'passenger')
        self.assertEqual(self.call('GET', '/me', token=second_device)[1]['account']['name'], 'New name')
        reopened = Store(self.path)
        self.assertEqual(reopened.dispatch('GET', '/me', {}, token)['account']['preferences'], prefs)
        other = {**self.data, 'email': 'other@example.test', 'name': 'Other'}
        self.call('POST', '/auth/register', other)
        self.assertEqual(self.call('GET', '/me', token=self.login(other))[1]['account']['name'], 'Other')
        self.assertEqual(self.call('POST', '/auth/logout', {}, token)[0], 200)
        self.assertEqual(self.call('GET', '/me', token=token)[0], 401)
        self.assertEqual(self.call('GET', '/me', token=second_device)[0], 200)
        self.call('PATCH', '/me', {'name': 'New name', 'preferences': {}}, second_device)
        self.assertEqual(self.call('GET', '/me', token=second_device)[1]['account']['preferences'], {})

    def test_five_failed_logins_restrict_retry_and_expire(self):
        self.call('POST', '/auth/register', self.data)
        for _ in range(5):
            self.assertEqual(self.call('POST', '/auth/login', {**self.data, 'password': 'Wrong-pass-123'})[0], 401)
        self.assertEqual(self.call('POST', '/auth/login', self.data)[0], 429)
        with self.server.store.connect() as db:
            db.execute('UPDATE failures SET at=at-901')
        self.login()

    def test_admin_only_summary_and_no_plaintext_password(self):
        self.server.store.register(self.data, role='admin')
        token = self.login()
        self.assertEqual(self.call('GET', '/admin/summary', token=token)[0], 200)
        with self.server.store.connect() as db:
            row = db.execute('SELECT * FROM accounts').fetchone()
            self.assertNotIn(self.data['password'], str(dict(row)))
            self.assertEqual(len(row['password_hash']), 64)
            db.execute('UPDATE sessions SET expires=0')
        self.assertEqual(self.call('GET', '/me', token=token)[0], 401)

    def test_concurrent_duplicate_registration(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.call('POST', '/auth/register', self.data)[0], range(2)))
        self.assertEqual(sorted(results), [200, 409])

if __name__ == '__main__':
    unittest.main()
