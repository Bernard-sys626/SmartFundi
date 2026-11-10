import 'package:flutter/material.dart';
import 'package:smartfundi_core/smartfundi_core.dart';
import 'package:provider/provider.dart';
import 'screens/client.dart';
import 'screens/fundi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const SmartFundiApp()));
  try {
    await Future.wait([state.init(), Future.delayed(const Duration(milliseconds: 2300))]);
  } catch (_) {}
  state.markReady();
}

class SmartFundiApp extends StatelessWidget {
  const SmartFundiApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      key: ValueKey(s.lang),
      debugShowCheckedModeBanner: false,
      title: 'SmartFundi',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      home: const Root(),
    );
  }
}

/// Chooses what to show. The role (client, fundi or admin) comes from the server at login,
/// so there is a single login for everyone.
class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.ready) return const SplashScreen();
    if (!s.langChosen) return const LanguageScreen();
    if (s.user == null) return const AuthScreen();
    switch (s.role) {
      case 'admin':
        return const UseAdminAppScreen();
      case 'fundi':
        if (s.user!['must_change_password'] == true) return const ForceChangePasswordScreen();
        return const FundiGate();
      default:
        final u = s.user!;
        if ((u['name'] ?? '').toString().isEmpty || u['district_id'] == null) return const OnboardingScreen();
        return const ClientShell();
    }
  }
}
