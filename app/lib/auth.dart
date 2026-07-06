import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'task_handler.dart';

class AuthResult {
  final bool ok;
  final String? error;
  const AuthResult(this.ok, [this.error]);
}

/// Account + credential handling. Talks to the backend for register/login and
/// stores a local salted hash so the OFF toggle can be verified even offline.
class Auth {
  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static String _normUrl(String u) {
    u = u.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static Future<String> serverUrl() async {
    final p = await _p;
    return _normUrl(p.getString(PrefKeys.serverUrl) ?? defaultServerUrl);
  }

  static Future<bool> isLoggedIn() async {
    final p = await _p;
    return (p.getString(PrefKeys.token) ?? '').isNotEmpty;
  }

  static String _hash(String pw, String salt) =>
      sha256.convert(utf8.encode('$salt|$pw')).toString();

  static Future<void> _storeCreds(
      SharedPreferences p, Map<String, dynamic> data, String password, String email) async {
    await p.setString(PrefKeys.token, data['token'] as String);
    await p.setString(PrefKeys.name, (data['name'] ?? 'Staff') as String);
    await p.setString(PrefKeys.email, email);

    final rnd = Random.secure();
    final salt = List.generate(8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await p.setString(PrefKeys.pwSalt, salt);
    await p.setString(PrefKeys.pwHash, _hash(password, salt));

    if ((p.getString(PrefKeys.deviceId) ?? '').isEmpty) {
      final id = List.generate(12, (_) => rnd.nextInt(16).toRadixString(16)).join();
      await p.setString(PrefKeys.deviceId, 'dev-$id');
    }
  }

  static Future<AuthResult> register(String name, String email, String password) =>
      _authCall('register', {'name': name, 'email': email, 'password': password}, email);

  static Future<AuthResult> login(String email, String password) =>
      _authCall('login', {'email': email, 'password': password}, email);

  static Future<AuthResult> _authCall(
      String path, Map<String, String> body, String email) async {
    final p = await _p;
    final url = _normUrl(p.getString(PrefKeys.serverUrl) ?? defaultServerUrl);
    try {
      final res = await http
          .post(
            Uri.parse('$url/api/v1/auth/$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        await _storeCreds(
            p, jsonDecode(res.body) as Map<String, dynamic>, body['password']!, email.trim().toLowerCase());
        return const AuthResult(true);
      }
      return AuthResult(false, _errText(res));
    } catch (_) {
      return const AuthResult(false, 'Cannot reach the server. Check internet and try again.');
    }
  }

  static String _errText(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      if (d is Map && d['detail'] is String) return d['detail'] as String;
    } catch (_) {}
    return 'Failed (HTTP ${res.statusCode})';
  }

  static Future<bool> checkLocalPassword(String password) async {
    final p = await _p;
    final salt = p.getString(PrefKeys.pwSalt) ?? '';
    final hash = p.getString(PrefKeys.pwHash) ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;
    return _hash(password, salt) == hash;
  }

  static Future<String> nameOf() async {
    final p = await _p;
    return p.getString(PrefKeys.name) ?? 'Staff';
  }

  static Future<void> logout() async {
    final p = await _p;
    await p.remove(PrefKeys.token);
    await p.remove(PrefKeys.pwSalt);
    await p.remove(PrefKeys.pwHash);
  }

  /// Best-effort tamper/lifecycle event (fire and forget).
  static Future<void> sendEvent(String type, {String? detail}) async {
    final p = await _p;
    final token = p.getString(PrefKeys.token) ?? '';
    if (token.isEmpty) return;
    final url = _normUrl(p.getString(PrefKeys.serverUrl) ?? defaultServerUrl);
    try {
      await http
          .post(
            Uri.parse('$url/api/v1/events'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'type': type,
              'detail': detail,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
