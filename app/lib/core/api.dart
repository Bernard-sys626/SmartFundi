import 'dart:convert';
import 'package:http/http.dart' as http;

/// Set at build time: --dart-define=API_BASE_URL=https://your-api.example.com/api
const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api');

/// 'main' = Client/Fundi app, 'admin' = SmartFundi Admin app (set in the entry point).
String appKind = 'main';

class ApiError implements Exception {
  final int status; // 0 = network, -1 = local (gps, etc)
  final String code;
  final Map<String, dynamic> data;
  ApiError(this.status, this.code, [this.data = const {}]);
}

class Api {
  static String? token;
  static void Function()? onUnauthorized;

  static Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};
  static Map<String, String> get _json => {'Content-Type': 'application/json', ...authHeaders};
  static String fileUrl(String id) => '$apiBase/files/$id';
  static Uri fileUri(String id) => Uri.parse('${fileUrl(id)}?token=${token ?? ''}');

  static Future<dynamic> _send(Future<http.Response> Function() f) async {
    http.Response r;
    try {
      r = await f().timeout(const Duration(seconds: 40));
    } catch (_) {
      throw ApiError(0, 'network');
    }
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    if (r.statusCode == 401) onUnauthorized?.call();
    final code = (body is Map && body['error'] is String) ? body['error'] as String : (r.statusCode >= 500 ? 'server' : 'generic');
    throw ApiError(r.statusCode, code, body is Map ? Map<String, dynamic>.from(body) : {});
  }

  static Future<dynamic> get(String p) => _send(() => http.get(Uri.parse('$apiBase$p'), headers: authHeaders));
  static Future<dynamic> post(String p, [Object? b]) =>
      _send(() => http.post(Uri.parse('$apiBase$p'), headers: _json, body: jsonEncode(b ?? {})));
  static Future<dynamic> put(String p, [Object? b]) =>
      _send(() => http.put(Uri.parse('$apiBase$p'), headers: _json, body: jsonEncode(b ?? {})));
  static Future<dynamic> delete(String p) => _send(() => http.delete(Uri.parse('$apiBase$p'), headers: authHeaders));

  static Future<Map<String, dynamic>> upload(String path) async {
    return await _send(() async {
      final req = http.MultipartRequest('POST', Uri.parse('$apiBase/files'));
      req.headers.addAll(authHeaders);
      req.files.add(await http.MultipartFile.fromPath('file', path));
      return http.Response.fromStream(await req.send());
    }).then((v) => Map<String, dynamic>.from(v as Map));
  }
}
