import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'i18n.dart';

const _fbKey = String.fromEnvironment('FIREBASE_API_KEY');
const _fbApp = String.fromEnvironment('FIREBASE_APP_ID');
const _fbSender = String.fromEnvironment('FIREBASE_SENDER_ID');
const _fbProject = String.fromEnvironment('FIREBASE_PROJECT_ID');

class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  bool ready = false;
  bool langChosen = false;
  String lang = 'sw';
  ThemeMode themeMode = ThemeMode.light;
  Map<String, dynamic>? user;
  Map<String, dynamic> config = {};
  List<Map<String, dynamic>> services = [];
  int unread = 0;
  Timer? _poll;
  bool _pushDone = false;

  String get role => (user?['role'] ?? '') as String;
  String get name => (user?['name'] ?? '') as String;
  String get locLabel => ready ? (prefs.getString('loc_label') ?? '') : '';
  num get commission => (config['commission_percent'] ?? 20) as num;
  Map<String, dynamic> get about => Map<String, dynamic>.from((config['about'] ?? {}) as Map);
  List<String> get supportPhones => [for (final p in (about['phones'] ?? []) as List) p.toString()];

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    langChosen = prefs.containsKey('lang');
    lang = prefs.getString('lang') ?? 'sw';
    currentLang = lang;
    themeMode = prefs.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    Api.token = prefs.getString('token');
    Api.onUnauthorized = logout;
    final u = prefs.getString('user');
    if (u != null && Api.token != null) user = Map<String, dynamic>.from(jsonDecode(u) as Map);
    await Future.wait([loadConfig(), loadServices(), if (Api.token != null) refreshMe()]);
    if (user != null) {
      _startPolling();
      initPush();
    }
  }

  void markReady() {
    ready = true;
    notifyListeners();
  }

  Future<void> loadConfig() async {
    try {
      config = Map<String, dynamic>.from(await Api.get('/config') as Map);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadServices() async {
    try {
      services = [for (final s in await Api.get('/services') as List) Map<String, dynamic>.from(s as Map)];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshMe() async {
    try {
      final r = await Api.get('/auth/me') as Map;
      setUser(Map<String, dynamic>.from(r['user'] as Map));
    } catch (_) {}
  }

  void setUser(Map<String, dynamic> u) {
    user = u;
    prefs.setString('user', jsonEncode(u));
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    lang = l;
    currentLang = l;
    langChosen = true;
    await prefs.setString('lang', l);
    notifyListeners();
    if (user != null) {
      try {
        await Api.put('/auth/me', {'language': l});
      } catch (_) {}
    }
  }

  void setDark(bool d) {
    themeMode = d ? ThemeMode.dark : ThemeMode.light;
    prefs.setString('theme', d ? 'dark' : 'light');
    notifyListeners();
  }

  void resetLang() {
    langChosen = false;
    prefs.remove('lang');
    notifyListeners();
  }

  void saveLocLabel(String l) => prefs.setString('loc_label', l);

  void login(String token, Map<String, dynamic> u) {
    Api.token = token;
    prefs.setString('token', token);
    // the language chosen on this device wins
    setUser(u);
    Api.put('/auth/me', {'language': lang}).catchError((_) {});
    _startPolling();
    initPush();
  }

  void logout() {
    if (user == null && Api.token == null) return;
    Api.token = null;
    user = null;
    unread = 0;
    _poll?.cancel();
    prefs.remove('token');
    prefs.remove('user');
    prefs.remove('loc_label');
    notifyListeners();
  }

  void _startPolling() {
    _poll?.cancel();
    refreshUnread();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refreshUnread());
  }

  Future<void> refreshUnread() async {
    if (Api.token == null) return;
    try {
      final r = await Api.get('/notifications/unread-count') as Map;
      final n = (r['unread'] ?? 0) as int;
      if (n != unread) {
        unread = n;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await Api.post('/notifications/read-all');
      unread = 0;
      notifyListeners();
    } catch (_) {}
  }

  /// Firebase push. Works only when the FIREBASE_* values were provided at build time.
  Future<void> initPush() async {
    if (_fbKey.isEmpty || _pushDone) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(apiKey: _fbKey, appId: _fbApp, messagingSenderId: _fbSender, projectId: _fbProject),
      );
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      final t = await m.getToken();
      if (t != null && Api.token != null) await Api.put('/auth/me', {'fcm_token': t});
      m.onTokenRefresh.listen((t) {
        if (Api.token != null) Api.put('/auth/me', {'fcm_token': t}).catchError((_) {});
      });
      _pushDone = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
