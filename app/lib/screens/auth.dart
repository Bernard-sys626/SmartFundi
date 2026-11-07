import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

/// One login for everybody: phone or email with a verification code.
/// The server decides if the account is Client, Fundi/Company or Admin.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  final _id = TextEditingController();
  String intent = 'client';

  Future<void> _request() async {
    final id = _id.text.trim();
    if (id.length < 5) return toast(context, tr('err_invalid_identifier'));
    String? dev;
    final ok = await busy(context, () async {
      final r = await Api.post('/auth/request-otp', {'identifier': id}) as Map;
      dev = r['dev_code']?.toString();
    });
    if (!ok || !mounted) return;
    final res = await showModalBottomSheet<Map>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _OtpSheet(identifier: id, intent: intent, devCode: dev),
    );
    if (res != null && mounted) {
      context.read<AppState>().login(res['token'] as String, Map<String, dynamic>.from(res['user'] as Map));
    }
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
          Center(child: Text(tr('tagline'), style: TextStyle(color: cs.secondary))),
          const SizedBox(height: 32),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'client', label: Text(tr('i_am_client'))),
              ButtonSegment(value: 'fundi', label: Text(tr('i_am_fundi'))),
            ],
            selected: {intent},
            onSelectionChanged: (v) => setState(() => intent = v.first),
            style: ButtonStyle(shape: WidgetStatePropertyAll(const StadiumBorder()), minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _id, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(hintText: tr('phone_or_email'), prefixIcon: const Icon(Icons.person_outline)),
            onSubmitted: (_) => _request(),
          ),
          const SizedBox(height: 16),
          PillButton(tr('get_code'), onPressed: _request),
          const SizedBox(height: 20),
          Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('or'))), const Expanded(child: Divider())]),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => toast(context, tr('google_soon')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder(), side: BorderSide(color: cs.outline)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SvgPicture.asset('assets/google_g.svg', width: 20, height: 20),
              const SizedBox(width: 12),
              Text(tr('continue_google'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 28),
          Center(child: TextButton(onPressed: () => context.read<AppState>().resetLang(), child: Text(tr('change_language')))),
        ]),
      ),
    );
  }
}

class _OtpSheet extends StatefulWidget {
  final String identifier, intent;
  final String? devCode;
  const _OtpSheet({required this.identifier, required this.intent, this.devCode});
  @override
  State<_OtpSheet> createState() => _OtpState();
}

class _OtpState extends State<_OtpSheet> {
  late final _code = TextEditingController(text: widget.devCode ?? '');

  Future<void> _verify() async {
    Map? res;
    final ok = await busy(context, () async {
      res = await Api.post('/auth/verify-otp', {
        'identifier': widget.identifier, 'code': _code.text.trim(), 'intent': widget.intent,
        'language': context.read<AppState>().lang,
      }) as Map;
    });
    if (ok && mounted) Navigator.pop(context, res);
  }

  Future<void> _resend() async {
    final ok = await busy(context, () async => await Api.post('/auth/request-otp', {'identifier': widget.identifier}));
    if (ok) toast(context, tr('code_sent'));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('enter_code'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(tr('code_sent_to', {'id': widget.identifier}), style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
        const SizedBox(height: 16),
        TextField(
          controller: _code, autofocus: true, keyboardType: TextInputType.number, maxLength: 6,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(counterText: ''),
        ),
        const SizedBox(height: 12),
        PillButton(tr('verify'), onPressed: _verify),
        TextButton(onPressed: _resend, child: Text(tr('resend_code'))),
      ]),
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
