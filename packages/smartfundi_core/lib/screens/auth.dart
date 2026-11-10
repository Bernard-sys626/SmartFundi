import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Animated logo on the blue splash screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(parent: _c, curve: const Interval(.35, 1, curve: Curves.easeIn));
    return Scaffold(
      backgroundColor: brandBlue,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(scale), child: FadeTransition(opacity: _c, child: const LogoMark(132))),
          const SizedBox(height: 24),
          FadeTransition(opacity: fade, child: const Wordmark(size: 40, color: Colors.white, accent: brandYellow)),
          const SizedBox(height: 14),
          FadeTransition(opacity: fade, child: Text(tr('tagline'), style: const TextStyle(color: Color(0xFFC9D6EA), letterSpacing: .5))),
          const SizedBox(height: 40),
          FadeTransition(opacity: fade, child: const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white54))),
        ]),
      ),
    );
  }
}

/// Language selection on first launch.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    Widget opt(String code, String label, String sub) => AppCard(
          onTap: () => s.setLang(code),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 32),
            const LogoMark(72),
            const SizedBox(height: 24),
            const Text('Chagua lugha / Choose language / Choisir la langue', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
            const SizedBox(height: 28),
            opt('sw', 'Kiswahili', 'Endelea kwa Kiswahili'),
            opt('en', 'English', 'Continue in English'),
            opt('fr', 'Français', 'Continuer en français'),
          ]),
        ),
      ),
    );
  }
}

/// Entry screen.
///  * Main app: two buttons. "Client" goes straight to the details form (no code). "Fundi / Company"
///    asks for a username and password (created the first time, then used on any phone).
///  * Admin app: username and password only.
class AuthScreen extends StatefulWidget {
  final bool admin;
  const AuthScreen({super.key, this.admin = false});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _phone = TextEditingController();
  String intent = ''; // '' = choose, 'fundi' = username and password form
  bool register = true; // fundi: first time = set username and password
  bool hide = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _user.text.trim(), p = _pass.text;
    if (u.length < 3 || u.contains(' ')) return toast(context, tr('err_invalid_username'));
    if (p.length < 6) return toast(context, tr('err_weak_password'));
    final reg = !widget.admin && register;
    if (reg && p != _pass2.text) return toast(context, tr('err_password_mismatch'));
    if (reg && _phone.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9) return toast(context, tr('err_invalid_phone'));
    Map? res;
    final ok = await busy(context, () async {
      res = await Api.post(reg ? '/auth/register' : '/auth/login', {
        'username': u, 'password': p, 'app': appKind, 'language': context.read<AppState>().lang,
        if (reg) 'phone': _phone.text.trim(),
      }) as Map;
    });
    if (ok && res != null && mounted) {
      context.read<AppState>().login(res!['token'] as String, Map<String, dynamic>.from(res!['user'] as Map));
    }
  }

  /// Forgot password: the Fundi enters the phone number registered in the app. The request goes to the
  /// Admins, who set a temporary password. Support numbers are shown so they can call.
  Future<void> _forgot() async {
    final s = context.read<AppState>();
    final ph = await inputSheet(context, title: tr('forgot_password'), label: tr('phone_registered'), type: TextInputType.phone, action: tr('send_request'));
    if (ph == null || ph.isEmpty || !mounted) return;
    final ok = await busy(context, () async => await Api.post('/auth/forgot', {'phone': ph}));
    if (!ok || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(tr('request_sent')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('forgot_info')),
          const SizedBox(height: 12),
          for (final p in s.supportPhones) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(p, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ok')))],
      ),
    );
  }

  Widget _credentials(ColorScheme cs) {
    final reg = !widget.admin && register;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.admin)
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: true, label: Text(tr('first_time'))),
            ButtonSegment(value: false, label: Text(tr('have_account'))),
          ],
          selected: {register},
          onSelectionChanged: (v) => setState(() => register = v.first),
        ),
      if (!widget.admin) const SizedBox(height: 16),
      if (reg) Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(tr('set_credentials_hint'), style: TextStyle(color: cs.secondary, height: 1.4))),
      TextField(
        controller: _user, keyboardType: TextInputType.visiblePassword, autocorrect: false, enableSuggestions: false, textInputAction: TextInputAction.next,
        decoration: InputDecoration(hintText: tr('username'), prefixIcon: const Icon(Icons.person_outline)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pass, obscureText: hide, autocorrect: false, enableSuggestions: false,
        textInputAction: reg ? TextInputAction.next : TextInputAction.done,
        onSubmitted: reg ? null : (_) => _submit(),
        decoration: InputDecoration(
          hintText: tr('password'), prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => hide = !hide)),
        ),
      ),
      if (reg) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _phone, keyboardType: TextInputType.phone,
          decoration: InputDecoration(hintText: tr('phone_registered'), prefixIcon: const Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass2, obscureText: hide, autocorrect: false, enableSuggestions: false, onSubmitted: (_) => _submit(),
          decoration: InputDecoration(hintText: tr('confirm_password'), prefixIcon: const Icon(Icons.lock_outline)),
        ),
        const SizedBox(height: 10),
        Text(tr('remember_credentials'), style: TextStyle(color: cs.secondary, fontSize: 12.5, height: 1.4)),
      ],
      const SizedBox(height: 16),
      PillButton(reg ? tr('create_account') : tr('login'), onPressed: _submit),
      if (!reg && !widget.admin) TextButton(onPressed: _forgot, child: Text(tr('forgot_password'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          const Center(child: LogoMark(96)),
          const SizedBox(height: 16),
          const Center(child: Wordmark(size: 34)),
          const SizedBox(height: 8),
          if (widget.admin)
            Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), decoration: BoxDecoration(color: brandYellow, borderRadius: BorderRadius.circular(20)), child: Text(tr('admin_badge'), style: const TextStyle(color: brandBlue, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12))))
          else
            Center(child: Text(tr('tagline'), style: TextStyle(color: cs.secondary))),
          const SizedBox(height: 32),
          if (widget.admin) ...[
            Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(tr('admin_only'), textAlign: TextAlign.center, style: TextStyle(color: cs.secondary, height: 1.4))),
            _credentials(cs),
          ] else if (intent.isEmpty) ...[
            // "Client" goes straight to the details form (no code). "Fundi or Company" asks for username and password.
            PillButton(tr('i_am_client'), icon: Icons.person_outline, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientStartScreen()))),
            const SizedBox(height: 14),
            PillButton(tr('i_am_fundi'), icon: Icons.engineering_outlined, outlined: true, onPressed: () => setState(() => intent = 'fundi')),
          ] else ...[
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => intent = ''), icon: const Icon(Icons.arrow_back), label: Text(tr('i_am_fundi')))),
            const SizedBox(height: 8),
            _credentials(cs),
          ],
          const SizedBox(height: 28),
          Center(child: TextButton(onPressed: () => context.read<AppState>().resetLang(), child: Text(tr('change_language')))),
        ]),
      ),
    );
  }
}

/// Client: fill in name, phone number and area, then go straight in. No verification code.
/// The phone number identifies the client, so the same number on another phone opens the same account.
class ClientStartScreen extends StatefulWidget {
  const ClientStartScreen({super.key});
  @override
  State<ClientStartScreen> createState() => _ClientStartState();
}

class _ClientStartState extends State<ClientStartScreen> {
  String name = '', phone = '';
  Map<String, dynamic>? loc;

  Future<void> _go() async {
    final s = context.read<AppState>();
    Map? res;
    final ok = await busy(context, () async {
      res = await Api.post('/auth/client-start', {
        'name': name, 'phone': phone, 'language': s.lang, 'app': appKind,
        'region_id': loc!['region_id'], 'district_id': loc!['district_id'], 'ward_id': loc!['ward_id'],
      }) as Map;
    });
    if (!ok || res == null || !mounted) return;
    s.saveLocLabel(loc!['label'] as String);
    if (loc!['active'] != true) toast(context, tr('err_area_not_available'));
    // Back to the root screen, which becomes the client's home as soon as the user is set.
    Navigator.of(context).popUntil((r) => r.isFirst);
    s.login(res!['token'] as String, Map<String, dynamic>.from(res!['user'] as Map));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(IconData i, String title, String value, VoidCallback f, bool done) => AppCard(
          onTap: f,
          child: Row(children: [
            CircleAvatar(backgroundColor: done ? const Color(0xFF2F855A) : cs.primary.withOpacity(.14), child: Icon(done ? Icons.check : i, color: done ? Colors.white : cs.primary)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(value.isEmpty ? tr('tap_to_set') : value, style: TextStyle(color: cs.secondary)),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        );
    final phoneOk = phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 9;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const LogoMark(64),
            const SizedBox(height: 20),
            Text(tr('welcome'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr('client_start_sub'), style: TextStyle(color: cs.secondary)),
            const SizedBox(height: 24),
            step(Icons.person_outline, tr('full_name'), name, () async {
              final v = await inputSheet(context, title: tr('full_name'), initial: name, label: tr('full_name_hint'));
              if (v != null && v.isNotEmpty) setState(() => name = v);
            }, name.isNotEmpty),
            step(Icons.phone_outlined, tr('phone'), phone, () async {
              final v = await inputSheet(context, title: tr('phone'), initial: phone, type: TextInputType.phone, label: '07XX XXX XXX');
              if (v != null && v.isNotEmpty) setState(() => phone = v);
            }, phoneOk),
            step(Icons.location_on_outlined, tr('your_area'), (loc?['label'] ?? '') as String, () async {
              final v = await pickLocation(context);
              if (v != null) setState(() => loc = v);
            }, loc != null),
            const Spacer(),
            PillButton(tr('continue'), onPressed: name.isNotEmpty && phoneOk && loc != null ? _go : null),
          ]),
        ),
      ),
    );
  }
}

/// First-time client setup, using popups: name, then Region > District > Ward.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends State<OnboardingScreen> {
  String name = '';
  Map<String, dynamic>? loc;

  @override
  void initState() {
    super.initState();
    final u = context.read<AppState>().user!;
    name = (u['name'] ?? '').toString();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final ok = await busy(context, () async {
      final r = await Api.put('/auth/me', {'name': name, 'region_id': loc!['region_id'], 'district_id': loc!['district_id'], 'ward_id': loc!['ward_id']}) as Map;
      s.saveLocLabel(loc!['label'] as String);
      s.setUser(Map<String, dynamic>.from(r['user'] as Map));
    });
    if (ok && mounted && loc!['active'] != true) toast(context, tr('err_area_not_available'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(IconData i, String title, String value, VoidCallback f, bool done) => AppCard(
          onTap: f,
          child: Row(children: [
            CircleAvatar(backgroundColor: done ? const Color(0xFF2F855A) : cs.primary.withOpacity(.14), child: Icon(done ? Icons.check : i, color: done ? Colors.white : cs.primary)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(value.isEmpty ? tr('tap_to_set') : value, style: TextStyle(color: cs.secondary)),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            const LogoMark(64),
            const SizedBox(height: 20),
            Text(tr('welcome'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr('onboarding_sub'), style: TextStyle(color: cs.secondary)),
            const SizedBox(height: 24),
            step(Icons.person_outline, tr('full_name'), name, () async {
              final v = await inputSheet(context, title: tr('full_name'), initial: name, label: tr('full_name_hint'));
              if (v != null && v.isNotEmpty) setState(() => name = v);
            }, name.isNotEmpty),
            step(Icons.location_on_outlined, tr('your_area'), (loc?['label'] ?? '') as String, () async {
              final v = await pickLocation(context);
              if (v != null) setState(() => loc = v);
            }, loc != null),
            const Spacer(),
            PillButton(tr('continue'), onPressed: name.isNotEmpty && loc != null ? _save : null),
            Center(child: TextButton(onPressed: () => context.read<AppState>().logout(), child: Text(tr('logout')))),
          ]),
        ),
      ),
    );
  }
}

/// Shown if an admin account somehow ends up in the Client/Fundi app.
class UseAdminAppScreen extends StatelessWidget {
  const UseAdminAppScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const LogoMark(80),
              const SizedBox(height: 20),
              Text(tr('err_use_admin_app'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: 24),
              PillButton(tr('logout'), outlined: true, onPressed: () => context.read<AppState>().logout()),
            ]),
          ),
        ),
      );
}

/// Shown to a Fundi after an Admin reset the password: a new password must be chosen before continuing.
class ForceChangePasswordScreen extends StatefulWidget {
  const ForceChangePasswordScreen({super.key});
  @override
  State<ForceChangePasswordScreen> createState() => _ForceChangeState();
}

class _ForceChangeState extends State<ForceChangePasswordScreen> {
  final _p1 = TextEditingController(), _p2 = TextEditingController();

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_p1.text.length < 6) return toast(context, tr('err_weak_password'));
    if (_p1.text != _p2.text) return toast(context, tr('err_password_mismatch'));
    final s = context.read<AppState>();
    final ok = await busy(context, () async {
      final r = await Api.post('/auth/set-password', {'password': _p1.text}) as Map;
      s.setUser(Map<String, dynamic>.from(r['user'] as Map));
    });
    if (ok && mounted) toast(context, tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          const Center(child: LogoMark(80)),
          const SizedBox(height: 20),
          Text(tr('set_new_password'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tr('set_new_password_sub'), style: TextStyle(color: cs.secondary, height: 1.4)),
          const SizedBox(height: 24),
          TextField(controller: _p1, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(hintText: tr('password'), prefixIcon: const Icon(Icons.lock_outline))),
          const SizedBox(height: 12),
          TextField(controller: _p2, obscureText: true, autocorrect: false, enableSuggestions: false, onSubmitted: (_) => _save(), decoration: InputDecoration(hintText: tr('confirm_password'), prefixIcon: const Icon(Icons.lock_outline))),
          const SizedBox(height: 20),
          PillButton(tr('save'), onPressed: _save),
          Center(child: TextButton(onPressed: () => context.read<AppState>().logout(), child: Text(tr('logout')))),
        ]),
      ),
    );
  }
}
