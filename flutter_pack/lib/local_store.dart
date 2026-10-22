import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class Account {
  final int id;
  final String name;
  final String login;
  final String role;
  final Map<String, dynamic> preferences;
  const Account(this.id, this.name, this.login,
    {this.role = 'passenger', this.preferences = const {}});
  factory Account.fromJson(Map<String, dynamic> json) => Account(
    json['id'] as int, json['name'] as String, json['email'] as String,
    role: json['role'] as String,
    preferences: Map<String, dynamic>.from(json['preferences'] as Map));
}

// Runs expensive password derivation off the UI isolate.
Future<String> passwordHash(List<String> values) async {
  final key = await Pbkdf2(macAlgorithm: Hmac.sha256(),
      iterations: 600000, bits: 256).deriveKeyFromPassword(
    password: values[0], nonce: base64Decode(values[1]),
  );
  return base64Encode(await key.extractBytes());
}

class LocalStore {
  final Database db;
  LocalStore._(this.db);

  static Future<LocalStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final db = sqlite3.open(p.join(dir.path, 'intermove_local_v1.sqlite'));
    db.execute('''CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL,
      login TEXT NOT NULL UNIQUE, salt TEXT NOT NULL, hash TEXT NOT NULL
    )''');
    return LocalStore._(db);
  }

  String? setting(String key) {
    db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }
  void saveSetting(String key, String value) {
    db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    db.execute('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', [key,value]);
  }

  int saveDraft(int? userId, Map<String, dynamic> payload) {
    db.execute('CREATE TABLE IF NOT EXISTS trip_drafts ('
      'id INTEGER PRIMARY KEY, user_id INTEGER, created_at TEXT NOT NULL, payload TEXT NOT NULL)');
    db.execute('INSERT INTO trip_drafts(user_id, created_at, payload) VALUES (?, ?, ?)',
      [userId, DateTime.now().toUtc().toIso8601String(), jsonEncode(payload)]);
    return db.lastInsertRowId;
  }

  Future<Account> register(String name, String login, String password) async {
    final normalized = login.trim().toLowerCase();
    if (db.select('SELECT id FROM users WHERE login = ?', [normalized]).isNotEmpty) {
      throw const FormatException('Этот логин уже занят.');
    }
    final random = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
    final hash = await compute(passwordHash, [password, salt]);
    try {
      db.execute('INSERT INTO users(name, login, salt, hash) VALUES (?, ?, ?, ?)',
          [name.trim(), normalized, salt, hash]);
    } on SqliteException {
      throw const FormatException('Не удалось создать профиль. Возможно, логин уже занят.');
    }
    return Account(db.lastInsertRowId, name.trim(), normalized);
  }

  Future<Account> login(String login, String password) async {
    final rows = db.select('SELECT * FROM users WHERE login = ?',
        [login.trim().toLowerCase()]);
    // Also derive for unknown users to avoid an immediate timing difference.
    final salt = rows.isEmpty
        ? base64Encode(List<int>.filled(16, 0)) : rows.first['salt'] as String;
    final actual = base64Decode(await compute(passwordHash, [password, salt]));
    final expected = rows.isEmpty
        ? List<int>.filled(32, 0) : base64Decode(rows.first['hash'] as String);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (rows.isEmpty || difference != 0) {
      throw const FormatException('Неверный логин или пароль.');
    }
    final row = rows.first;
    return Account(row['id'] as int, row['name'] as String, row['login'] as String);
  }
}
