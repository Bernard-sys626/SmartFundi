import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smartfundi_core/smartfundi_core.dart';
import 'package:provider/provider.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});
  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: IndexedStack(index: idx, children: [
        ClientHome(onSeeAll: () => setState(() => idx = 1)),
        const MyRequestsPage(),
        const NotificationsPage(embedded: true),
        const MessagesPage(),
        const SettingsPage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          setState(() => idx = i);
          if (i == 2) Future.delayed(const Duration(seconds: 2), s.markAllRead);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: tr('requests')),
          NavigationDestination(icon: Badge(isLabelVisible: s.unread > 0, label: Text('${s.unread}'), child: const Icon(Icons.notifications_outlined)), selectedIcon: const Icon(Icons.notifications), label: tr('notifications')),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: tr('messages')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: tr('settings')),
        ],
      ),
    );
  }
}

class ClientHome extends StatelessWidget {
  final VoidCallback onSeeAll;
  const ClientHome({super.key, required this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final first = s.name.split(' ').first;
    return SafeArea(
      child: Loader<List<J>>(
        load: () async => asList(await Api.get('/jobs')),
        every: const Duration(seconds: 20),
        builder: (c, jobs, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
            Row(children: [
              const LogoMark(40),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('hello', {'name': first}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (s.locLabel.isNotEmpty) Text(s.locLabel, style: TextStyle(color: cs.secondary, fontSize: 12.5)),
              ])),
              const BellButton(),
            ]),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(32)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('home_title'), style: TextStyle(color: cs.onPrimary, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 8),
                Text(tr('home_sub'), style: TextStyle(color: cs.onPrimary.withOpacity(.8))),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportFlow())),
                  icon: const Icon(Icons.bolt),
                  label: Text(tr('report_problem'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), shape: const StadiumBorder(), backgroundColor: cs.onPrimary, foregroundColor: cs.primary),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            AppCard(child: Row(children: [const Icon(Icons.verified_user_outlined), const SizedBox(width: 12), Expanded(child: Text(tr('pay_in_app'), style: const TextStyle(height: 1.4)))])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(tr('recent_requests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              if (jobs.isNotEmpty) TextButton(onPressed: onSeeAll, child: Text(tr('see_all'))),
            ]),
            const SizedBox(height: 8),
            if (jobs.isEmpty) EmptyView(tr('no_requests_yet'), icon: Icons.receipt_long_outlined) else for (final j in jobs.take(3)) JobCard(j),
          ]),
        ),
      ),
    );
  }
}

class MyRequestsPage extends StatelessWidget {
  const MyRequestsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('requests'))),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/jobs')),
        every: const Duration(seconds: 15),
        builder: (c, jobs, reload) => jobs.isEmpty
            ? EmptyView(tr('no_requests_yet'), icon: Icons.receipt_long_outlined)
            : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.all(16), children: [for (final j in jobs) JobCard(j)])),
      ),
    );
  }
}

// ===================================================================== report a problem
class ReportFlow extends StatefulWidget {
  const ReportFlow({super.key});
  @override
  State<ReportFlow> createState() => _ReportFlowState();
}

class _ReportFlowState extends State<ReportFlow> {
  final _page = PageController();
  int step = 0;
  int? serviceId;
  String pref = 'technician';
  final _desc = TextEditingController();
  final _landmark = TextEditingController();
  final List<String> photos = [];
  Map<String, dynamic>? loc;
  double? lat, lng;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final u = s.user!;
    if (u['district_id'] != null) {
      loc = {'region_id': u['region_id'], 'district_id': u['district_id'], 'ward_id': u['ward_id'], 'label': s.locLabel, 'active': true};
    }
  }

  bool get _valid {
    switch (step) {
      case 0:
        return serviceId != null;
      case 1:
        return _desc.text.trim().isNotEmpty;
      case 2:
        return loc != null && lat != null;
      default:
        return true;
    }
  }

  void _go(int to) {
    setState(() => step = to);
    _page.animateToPage(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _gps() async {
    final p = await busyVal(context, getPosition);
    if (p != null) setState(() {
      lat = p.latitude;
      lng = p.longitude;
    });
  }

  Future<void> _submit() async {
    final res = await busyVal<J>(context, () async {
      final ids = <String>[];
      for (final p in photos) {
        ids.add((await Api.upload(p))['id'] as String);
      }
      return asMap(await Api.post('/jobs', {
        'service_id': serviceId, 'preference': pref, 'description': _desc.text.trim(), 'address': _landmark.text.trim(),
        'region_id': loc!['region_id'], 'district_id': loc!['district_id'], 'ward_id': loc!['ward_id'],
        'lat': lat, 'lng': lng, 'photo_ids': ids,
      }));
    });
    if (res != null && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReportSuccess(job: res)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final titles = [tr('step_service'), tr('step_describe'), tr('step_location'), tr('step_review')];
    return Scaffold(
      appBar: AppBar(title: Text(tr('report_problem')), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => step == 0 ? Navigator.pop(context) : _go(step - 1))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [for (var i = 0; i < 4; i++) Expanded(child: Container(height: 5, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: i <= step ? cs.primary : cs.outline, borderRadius: BorderRadius.circular(3))))]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(titles[step], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)))),
        Expanded(
          child: PageView(controller: _page, physics: const NeverScrollableScrollPhysics(), children: [
            // 1. service
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              for (final sv in s.services)
                AppCard(
                  onTap: () => setState(() => serviceId = sv['id'] as int),
                  color: serviceId == sv['id'] ? cs.primary.withOpacity(.1) : null,
                  child: Row(children: [
                    Expanded(child: Text(svcName(sv), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Icon(serviceId == sv['id'] ? Icons.radio_button_checked : Icons.radio_button_off, color: cs.primary),
                  ]),
                ),
              const SizedBox(height: 8),
              Text(tr('who_do_you_prefer'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [ButtonSegment(value: 'technician', label: Text(tr('pref_technician'))), ButtonSegment(value: 'company', label: Text(tr('pref_company')))],
                selected: {pref},
                onSelectionChanged: (v) => setState(() => pref = v.first),
                style: const ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder()), minimumSize: WidgetStatePropertyAll(Size(0, 48))),
              ),
            ]),
            // 2. describe
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              TextField(controller: _desc, maxLines: 5, minLines: 4, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: tr('describe_hint'))),
              const SizedBox(height: 16),
              Text(tr('photos_optional'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in photos)
                  Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(p), width: 84, height: 84, fit: BoxFit.cover)),
                    Positioned(right: -6, top: -6, child: GestureDetector(onTap: () => setState(() => photos.remove(p)), child: CircleAvatar(radius: 12, backgroundColor: cs.error, child: const Icon(Icons.close, size: 14, color: Colors.white)))),
                  ]),
                if (photos.length < 5)
                  GestureDetector(
                    onTap: () async {
                      final r = await pickImages(context);
                      setState(() => photos.addAll(r.take(5 - photos.length)));
                    },
                    child: Container(width: 84, height: 84, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.add_a_photo_outlined)),
                  ),
              ]),
            ]),
            // 3. location
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              AppCard(
                onTap: () async {
                  final v = await pickLocation(context);
                  if (v != null) setState(() => loc = v);
                },
                child: Row(children: [
                  const Icon(Icons.location_city_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('problem_area'), style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                    Text(((loc?['label'] ?? '') as String).isEmpty ? tr('tap_to_set') : loc!['label'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ])),
                  const Icon(Icons.chevron_right),
                ]),
              ),
              if (loc != null && loc!['active'] != true) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(tr('err_area_not_available'), style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('share_gps'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(tr('share_gps_sub'), style: TextStyle(color: cs.secondary)),
                  const SizedBox(height: 12),
                  PillButton(lat == null ? tr('share_location') : tr('location_shared'), icon: lat == null ? Icons.my_location : Icons.check_circle, outlined: lat != null, onPressed: _gps),
                  if (lat != null) TextButton(onPressed: () => openUri(context, mapsUri(lat!, lng!)), child: Text(tr('open_map'))),
                ]),
              ),
              TextField(controller: _landmark, decoration: InputDecoration(hintText: tr('landmark_hint'))),
            ]),
            // 4. review
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              AppCard(
                child: Column(children: [
                  RowInfo(tr('service'), s.services.where((x) => x['id'] == serviceId).map(svcName).join()),
                  RowInfo(tr('prefers'), tr(pref == 'company' ? 'pref_company' : 'pref_technician')),
                  RowInfo(tr('area'), ((loc?['label'] ?? '') as String)),
                  RowInfo(tr('gps'), lat == null ? '-' : tr('location_shared')),
                  RowInfo(tr('photos'), '${photos.length}'),
                  const Divider(height: 20),
                  Align(alignment: Alignment.centerLeft, child: Text(_desc.text.trim(), style: const TextStyle(height: 1.4))),
                ]),
              ),
              const NauliNotice(),
            ]),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: PillButton(step == 3 ? tr('accept_and_send') : tr('next'), onPressed: _valid ? (step == 3 ? _submit : () => _go(step + 1)) : null),
          ),
        ),
      ]),
    );
  }
}

class ReportSuccess extends StatelessWidget {
  final J job;
  const ReportSuccess({super.key, required this.job});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircleAvatar(radius: 44, backgroundColor: Color(0xFF2F855A), child: Icon(Icons.check, size: 52, color: Colors.white)),
            const SizedBox(height: 24),
            Text(tr('request_sent'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(job['code'].toString(), style: TextStyle(fontSize: 18, color: cs.secondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(tr('request_sent_sub'), textAlign: TextAlign.center, style: TextStyle(color: cs.secondary, height: 1.4)),
            const SizedBox(height: 32),
            PillButton(tr('track_request'), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: job['id'] as String)))),
            const SizedBox(height: 10),
            PillButton(tr('back_home'), outlined: true, onPressed: () => Navigator.pop(context)),
          ]),
        ),
      ),
    );
  }
}
