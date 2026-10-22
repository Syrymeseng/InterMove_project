"""InterMove teaching API. Standard library; use TLS for device-to-device access."""
from contextlib import contextmanager
import threading
import journeys
import v7
import urban_osm
import argparse
import getpass
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import ssl
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCHEMA = '''
CREATE TABLE IF NOT EXISTS accounts (
 id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL,
 salt TEXT NOT NULL, password_hash TEXT NOT NULL,
 role TEXT NOT NULL CHECK(role IN ('passenger','operator','admin')),
 preferences TEXT NOT NULL DEFAULT '{}');
CREATE TABLE IF NOT EXISTS sessions (
 token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL REFERENCES accounts(id),
 expires REAL NOT NULL);
CREATE TABLE IF NOT EXISTS failures(email TEXT NOT NULL, at REAL NOT NULL);
CREATE INDEX IF NOT EXISTS failure_lookup ON failures(email,at);
CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, actor INTEGER,
 event TEXT NOT NULL, at REAL NOT NULL);
'''

class ApiError(Exception):
    def __init__(self, status, message, field=None):
        self.status, self.message, self.field = status, message, field


def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt),
                          n=32768, r=8, p=1, maxmem=64*1024*1024, dklen=32).hex()


def text(data, key, minimum=1, maximum=254):
    value = data.get(key)
    if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum:
        raise ApiError(400, f'Check field {key}.', key)
    return value.strip()


def email_value(data):
    value = text(data, 'email').lower()
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
        raise ApiError(400, 'Enter a valid email.', 'email')
    return value


def password_value(data):
    value = data.get('password')
    if not isinstance(value, str) or not 8 <= len(value) <= 128:
        raise ApiError(400, 'Password must contain 8–128 characters.', 'password')
    return value


def preferences_value(data):
    value = data.get('preferences', {})
    allowed = {'stepFree', 'boardingAssistance', 'wheelchair', 'locale', 'currency', 'avatar', 'marker'}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ApiError(400, 'Invalid preferences.', 'preferences')
    for key in ('stepFree', 'boardingAssistance'):
        if key in value and type(value[key]) is not bool:
            raise ApiError(400, 'Invalid preferences.', 'preferences')
    if 'wheelchair' in value and value['wheelchair'] not in ('none', 'folded', 'seated'):
        raise ApiError(400, 'Invalid wheelchair preference.', 'preferences')
    for key, options in {'locale':('en','ru','kk'),'currency':('KZT','USD','EUR'),
                          'avatar':('plain','blue','gold'),'marker':('pin','circle','flag')}.items():
        if key in value and value[key] not in options:
            raise ApiError(400, 'Invalid preference: '+key, 'preferences')
    return value


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.connect() as db:
            db.executescript(SCHEMA + journeys.SCHEMA)
            journeys.seed(db)
            db.executescript(v7.SCHEMA)
            v7.seed(db)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def account(row):
        return dict(id=row['id'], name=row['name'], email=row['email'],
                    role=row['role'], preferences=json.loads(row['preferences']))

    def register(self, data, role='passenger'):
        name, email, password = text(data, 'name', maximum=60), email_value(data), password_value(data)
        salt = secrets.token_hex(16)
        digest = password_hash(password, salt)
        with self.connect() as db:
            try:
                cursor = db.execute('INSERT INTO accounts(name,email,salt,password_hash,role) VALUES(?,?,?,?,?)',
                                    (name, email, salt, digest, role))
            except sqlite3.IntegrityError:
                raise ApiError(409, 'This email is already registered.', 'email')
            db.execute('INSERT INTO audit(actor,event,at) VALUES(?,?,?)',
                       (cursor.lastrowid, 'account_created', time.time()))
            return self.account(db.execute('SELECT * FROM accounts WHERE id=?', (cursor.lastrowid,)).fetchone())

    def login(self, data):
        email, password = email_value(data), password_value(data)
        denied = False
        now = time.time()
        # Serializes failed-attempt accounting as well as concurrent sign-ins.
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM failures WHERE at <= ?', (now-900,))
            if db.execute('SELECT count(*) FROM failures WHERE email=?', (email,)).fetchone()[0] >= 5:
                raise ApiError(429, 'Too many failed attempts. Retry after 15 minutes.')
            row = db.execute('SELECT * FROM accounts WHERE email=?', (email,)).fetchone()
            digest = password_hash(password, row['salt'] if row else '00'*16)
            if row is None or not hmac.compare_digest(digest, row['password_hash']):
                db.execute('INSERT INTO failures VALUES(?,?)', (email, now))
                denied = True
            else:
                db.execute('DELETE FROM failures WHERE email=?', (email,))
                db.execute('DELETE FROM sessions WHERE expires<=?', (now,))
                token = secrets.token_urlsafe(32)
                db.execute('INSERT INTO sessions VALUES(?,?,?)',
                           (hashlib.sha256(token.encode()).hexdigest(), row['id'], now+86400))
                result = {'account': self.account(row), 'token': token}
        if denied:
            raise ApiError(401, 'Incorrect email or password.')
        return result

    def dispatch(self, method, path, data, token):
        if method == 'GET' and path == '/health':
            return {'status': 'ok', 'demo': True}
        if method == 'POST' and path == '/auth/register':
            # Client-supplied role/id are never accepted by registration.
            return {'account': self.register(data)}
        if method == 'POST' and path == '/auth/login':
            return self.login(data)
        if path=='/transit/osm' and method=='GET':
            return urban_osm.catalogue(self.path)
        if path=='/transit/osm/plan' and method=='POST':
            try:return urban_osm.plan(urban_osm.catalogue(self.path),data)
            except ValueError as e:raise ApiError(400,str(e))
        if path in ('/catalog','/search'):
            with self.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                return journeys.dispatch(db,method,path,data,None,ApiError)
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT a.* FROM accounts a JOIN sessions s ON a.id=s.account_id '
                             'WHERE s.token_hash=? AND s.expires>?', (token_hash, time.time())).fetchone()
            if row is None:
                raise ApiError(401, 'Session expired. Sign in again.')
            if method == 'POST' and path == '/auth/logout':
                db.execute('DELETE FROM sessions WHERE token_hash=?', (token_hash,))
                return {'ok': True}
            if method == 'GET' and path == '/me':
                return {'account': self.account(row)}
            if method == 'PATCH' and path == '/me':
                name = text(data, 'name', maximum=60)
                prefs = preferences_value(data)
                db.execute('UPDATE accounts SET name=?,preferences=? WHERE id=?',
                           (name, json.dumps(prefs), row['id']))
                db.execute('INSERT INTO audit(actor,event,at) VALUES(?,?,?)',
                           (row['id'], 'profile_updated', time.time()))
                return {'account': self.account(db.execute('SELECT * FROM accounts WHERE id=?', (row['id'],)).fetchone())}
            if method == 'GET' and path == '/admin/summary':
                if row['role'] != 'admin':
                    raise ApiError(403, 'Administrator access required.')
                return {'accounts': db.execute('SELECT count(*) FROM accounts').fetchone()[0],
                        'auditEvents': db.execute('SELECT count(*) FROM audit').fetchone()[0]}
            return journeys.dispatch(db,method,path,data,row,ApiError)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, *_):
        pass  # No credentials, bearer tokens, query strings or bodies in logs.

    def handle_api(self):
        try:
            if '?' in self.path:
                raise ApiError(400, 'URL query parameters are not supported.')
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > 16384:
                raise ApiError(413, 'Request body too large.')
            if self.headers.get('Transfer-Encoding'):
                raise ApiError(400, 'Content-Length required.')
            data = json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(data, dict):
                raise ApiError(400, 'JSON object required.')
            auth = self.headers.get('Authorization', '')
            token = auth[7:] if auth.startswith('Bearer ') else ''
            result = self.server.store.dispatch(self.command, self.path, data, token)
            status = 200
        except ApiError as e:
            status, result = e.status, {'error': e.message, 'field': e.field}
        except (ValueError, UnicodeError, TypeError, KeyError):
            status, result = 400, {'error': 'Invalid request.'}
        except Exception:
            status, result = 500, {'error': 'Server error. Retry later.'}
        body = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PATCH = handle_api


def make_server(path, host='127.0.0.1', port=8787):
    server = ThreadingHTTPServer((host, port), Handler)
    server.store = Store(path)
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default='intermove.sqlite')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--cert')
    parser.add_argument('--key')
    parser.add_argument('--local-dev', action='store_true')
    parser.add_argument('--create-staff', choices=['admin', 'operator'])
    args = parser.parse_args()
    if args.create_staff:
        account = Store(args.db).register({'name': input('Name: '), 'email': input('Email: '),
            'password': getpass.getpass('Password (8–128 characters): ')}, args.create_staff)
        print('Created', account['role'], account['id'])
        return
    tls = bool(args.cert and args.key)
    if not tls and not (args.local_dev and args.host == '127.0.0.1'):
        parser.error('Use --cert/--key for HTTPS; --local-dev is restricted to 127.0.0.1.')
    server = make_server(args.db, args.host, args.port)
    if tls:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f'InterMove demo API: {"https" if tls else "http"}://{args.host}:{args.port}')
    stopping = threading.Event()
    def cleanup():
        while not stopping.wait(15):
            try:
                with server.store.connect() as db:
                    db.execute('BEGIN IMMEDIATE')
                    journeys.expire(db)
            except sqlite3.Error:
                pass
    worker = threading.Thread(target=cleanup, daemon=True)
    worker.start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stopping.set()
        worker.join(timeout=20)
        server.server_close()

if __name__ == '__main__':
    main()
