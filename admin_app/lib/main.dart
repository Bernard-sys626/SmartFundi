import 'package:flutter/material.dart';
import 'package:smartfundi_core/smartfundi_core.dart';
import 'package:provider/provider.dart';
import 'screens/admin.dart';

/// SmartFundi Admin: a separate app for administrators only.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appKind = 'admin';
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const SmartFundiAdminApp()));
  try {
    await Future.wait([state.init(), Future.delayed(const Duration(milliseconds: 2000))]);
  } catch (_) {}
  state.markReady();
}

class SmartFundiAdminApp extends StatelessWidget {
  const SmartFundiAdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      key: ValueKey(s.lang),
      debugShowCheckedModeBanner: false,
      title: 'SmartFundi Admin',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      home: const _AdminRoot(),
    );
  }
}

class _AdminRoot extends StatelessWidget {
  const _AdminRoot();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.ready) return const SplashScreen();
    if (!s.langChosen) return const LanguageScreen();
    if (s.user == null) return const AuthScreen(admin: true);
    if (s.role != 'admin') {
      // not an admin account: never show anything, go back to the login
      WidgetsBinding.instance.addPostFrameCallback((_) => s.logout());
      return const SplashScreen();
    }
    return const AdminShell();
  }
}
