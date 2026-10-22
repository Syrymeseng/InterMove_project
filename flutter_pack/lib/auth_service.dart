import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'local_store.dart';

const backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');

class AuthService {
  final LocalStore? local;
  String? _token;
  int _generation=0;
  Account? account;
  final http.Client _client = http.Client();
  final void Function()? onSessionExpired;
  late String _endpoint;
  String get endpoint=>_endpoint;
  AuthService(this.local, {this.onSessionExpired}) {
    String? saved;
    try {saved=local?.setting('backend_url');}catch(_) {}
    _endpoint=saved ?? (backendUrl.isNotEmpty?backendUrl:
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux?'http://127.0.0.1:8787':''));
  }
  static String validateEndpoint(String value) {
    final clean=value.trim().replaceAll(RegExp(r'/+$'),'');
    if(clean.isEmpty)return '';
    final uri=Uri.tryParse(clean);
    if(uri==null || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      !(uri.scheme=='https' || (uri.scheme=='http' && uri.host=='127.0.0.1'))) {
      throw const FormatException('Нужен HTTPS-адрес сервера. Для этого компьютера разрешён http://127.0.0.1:8787.');
    }
    return clean;
  }
  void configure(String value) {
    final next=validateEndpoint(value);
    local?.saveSetting('backend_url',next);
    if(next!=_endpoint){_generation++;_endpoint=next;_token=null;account=null;onSessionExpired?.call();}
  }
  Future<void> checkConnection(String value) async {
    final target=validateEndpoint(value);
    if(target.isEmpty)throw const FormatException('Введите адрес сервера.');
    final response=await _client.get(Uri.parse('$target/health')).timeout(const Duration(seconds:8));
    final data=jsonDecode(response.body);
    if(response.statusCode!=200 || data is! Map || data['status']!='ok')throw const FormatException('Сервер InterMove не найден по этому адресу.');
  }
  bool get remote => endpoint.isNotEmpty;
  bool get available => remote || local != null;

  Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final generation=_generation;
    final base = Uri.parse(endpoint);
    if (base.scheme != 'https' && !(base.scheme == 'http' && base.host == '127.0.0.1')) {
      throw const FormatException('HTTPS is required. HTTP is allowed only on 127.0.0.1 for local development.');
    }
    final request = http.Request(method,
      Uri.parse('${endpoint}$path'));
    request.headers['Content-Type'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request)
      .timeout(Duration(seconds:path.startsWith('/transit/osm')?45:20))).timeout(Duration(seconds:path.startsWith('/transit/osm')?45:20));
    if(generation!=_generation)throw const FormatException('Сервер изменён. Повторите действие на выбранном сервере.');
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode == 401 && path != '/auth/login') {
      _token = null;
      account = null;
      onSessionExpired?.call();
      if (path == '/auth/logout') return {'ok': true};
    }
    if (response.statusCode >= 400) {
      throw FormatException(data['error'] as String? ?? 'Server error. Retry later.');
    }
    return data;
  }

  Future<Account> login(String email, String password) async {
    if (!remote) return account = await local!.login(email, password);
    final data = await _request('POST', '/auth/login', {'email': email, 'password': password});
    _token = data['token'] as String;
    return account = Account.fromJson(data['account'] as Map<String, dynamic>);
  }

  Future<Account> register(String name, String email, String password) async {
    if (!remote) return account = await local!.register(name, email, password);
    await _request('POST', '/auth/register', {'name': name, 'email': email, 'password': password});
    return login(email, password);
  }

  Future<void> logout() async {
    if (remote && _token != null) await _request('POST', '/auth/logout');
    _token = null;
    account = null;
  }

  Future<Account> updateProfile(String name, Map<String, dynamic> preferences) async {
    final data = await _request('PATCH', '/me', {'name': name, 'preferences': preferences});
    return account = Account.fromJson(data['account'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> api(String method, String path, [Map<String, dynamic>? body]) {
    if (!remote) throw const FormatException('Укажите адрес сервера в настройках приложения и запустите Python-сервер.');
    return _request(method, path, body);
  }

  Future<Map<String, dynamic>> adminSummary() => _request('GET', '/admin/summary');
  void close() => _client.close();
}
