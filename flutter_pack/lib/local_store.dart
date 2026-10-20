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
  const Account(this.id, this.name, this.login);
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
