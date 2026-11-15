import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smartfundi_core/smartfundi_core.dart';
import 'package:provider/provider.dart';

IconData catIcon(Map c) {
  switch ((c['icon'] ?? '').toString()) {
    case 'bolt':
    case 'electrical_services':
      return Icons.electrical_services;
    case 'car_repair':
      return Icons.car_repair;
    case 'plumbing':
      return Icons.plumbing;
    case 'handyman':
      return Icons.handyman;
    case 'construction':
      return Icons.construction;
    default:
      return Icons.build_circle_outlined;
  }
}

String catName(Map c) => (c['name_$currentLang'] ?? c['name_en'] ?? '').toString();

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
      body: LazyIndexedStack(index: idx, builders: [
        () => ClientHome(onSeeAll: () => setState(() => idx = 1)),
        () => const MyRequestsPage(),
        () => const MyFundisPage(),
        () => const MessagesPage(),
        () => const SettingsPage(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: tr('requests')),
          NavigationDestination(icon: const Icon(Icons.engineering_outlined), selectedIcon: const Icon(Icons.engineering), label: tr('my_fundi')),
          NavigationDestination(icon: Badge(isLabelVisible: s.unread > 0, label: Text('${s.unread}'), child: const Icon(Icons.chat_bubble_outline)), selectedIcon: const Icon(Icons.chat_bubble), label: tr('messages')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: tr('settings')),
        ],
      ),
    );
  }
}

// ===================================================================== home
class ClientHome extends StatefulWidget {
  final VoidCallback onSeeAll;
  const ClientHome({super.key, required this.onSeeAll});
  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  Map<String, dynamic>? loc; // filter: region / district / ward
  int? catId;
  String type = '';
  int _k = 0;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final u = s.user!;
    if (u['district_id'] != null) {
      loc = {'region_id': u['region_id'], 'district_id': u['district_id'], 'ward_id': null, 'label': s.locLabel};
    }
  }

  String get _query {
    final p = <String>[];
    if (loc?['region_id'] != null) p.add('region_id=${loc!['region_id']}');
    if (loc?['district_id'] != null) p.add('district_id=${loc!['district_id']}');
    if (loc?['ward_id'] != null) p.add('ward_id=${loc!['ward_id']}');
    if (catId != null) p.add('category_id=$catId');
    if (type.isNotEmpty) p.add('type=$type');
    return p.join('&');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final first = s.name.split(' ').first;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => setState(() => _k++),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
          Row(children: [
            const LogoMark(40),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('hello', {'name': first}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (s.locLabel.isNotEmpty) Text(s.locLabel, style: TextStyle(color: cs.secondary, fontSize: 12.5)),
            ])),
            IconButton(tooltip: tr('help'), icon: const Icon(Icons.help_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage(kind: 'client')))),
            const BellButton(),
          ]),
          const SizedBox(height: 14),
          const MediaCarousel(placement: 'home'),
          HeroCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('home_title'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text(tr('home_sub'), style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportFlow())),
                icon: const Icon(Icons.bolt),
                label: Text(tr('report_problem'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder(), backgroundColor: brandOrange, foregroundColor: Colors.white),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          // ---- categories
          if (s.categories.isNotEmpty) ...[
            SectionTitle(tr('categories')),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal, itemCount: s.categories.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = s.categories[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportFlow(categoryId: c['id'] as int))),
                    child: Container(
                      width: 118, padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CircleAvatar(radius: 22, backgroundColor: brandSky.withOpacity(.15), child: Icon(catIcon(c), color: brandSky)),
                        const SizedBox(height: 8),
                        Text(catName(c), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
          ],
          // ---- fundi directory with filters
          SectionTitle(tr('choose_fundi_title')),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ActionChip(
              avatar: const Icon(Icons.location_on_outlined, size: 18),
              label: Text(loc == null ? tr('filter_area') : (loc!['label'] ?? '').toString()),
              onPressed: () async {
                final v = await pickLocation(context, wholeDistrict: true);
                if (v != null) setState(() => loc = v);
              },
            ),
            if (loc != null) ActionChip(avatar: const Icon(Icons.close, size: 16), label: Text(tr('all_areas')), onPressed: () => setState(() => loc = null)),
            ChoiceChip(label: Text(tr('pref_technician')), selected: type == 'technician', onSelected: (v) => setState(() => type = v ? 'technician' : '')),
            ChoiceChip(label: Text(tr('pref_company')), selected: type == 'company', onSelected: (v) => setState(() => type = v ? 'company' : '')),
          ]),
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in s.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6),
                  child: FilterChip(label: Text(catName(c)), selected: catId == c['id'], onSelected: (v) => setState(() => catId = v ? c['id'] as int : null)),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Loader<List<J>>(
            key: ValueKey('$_query#$_k'),
            load: () async => asList(await Api.get('/directory/fundis?$_query')),
            builder: (c, list, _) => list.isEmpty
                ? EmptyView(tr('no_fundis_found'), icon: Icons.search_off)
                : Column(children: [for (final f in list) FundiTile(f)]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(tr('recent_requests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            TextButton(onPressed: widget.onSeeAll, child: Text(tr('see_all'))),
          ]),
          Loader<List<J>>(
            key: ValueKey('jobs$_k'),
            load: () async => asList(await Api.get('/jobs')),
            builder: (c, jobs, _) => jobs.isEmpty ? EmptyView(tr('no_requests_yet'), icon: Icons.receipt_long_outlined) : Column(children: [for (final j in jobs.take(3)) JobCard(j)]),
          ),
        ]),
      ),
    );
  }
}

/// One Fundi / Company in the list (name, stars, kind, categories). Tap = full profile.
class FundiTile extends StatelessWidget {
  final J f;
  const FundiTile(this.f, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = f['rating'] is Map ? (f['rating'] as Map)['avg'] : null;
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FundiProfilePage(id: f['id'] as String))),
      child: Row(children: [
        Avatar(fileId: f['photo_file_id'] as String?, name: who(f), size: 52),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who(f), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          Row(children: [
            Text(tr(f['fundi_type'] == 'company' ? 'pref_company' : 'pref_technician'), style: TextStyle(color: cs.secondary, fontSize: 12.5)),
            if (r != null) ...[const SizedBox(width: 8), Stars((r as num).toDouble(), size: 15)],
          ]),
          if ((f['categories'] ?? '').toString().isNotEmpty) Text(f['categories'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          if ((f['services'] ?? '').toString().isNotEmpty) Text(f['services'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.secondary, fontSize: 12.5)),
        ])),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}

class FundiProfilePage extends StatelessWidget {
  final String id;
  const FundiProfilePage({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('fundi'))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/directory/fundis/$id')),
        builder: (c, f, _) {
          final r = f['rating'] is Map ? (f['rating'] as Map)['avg'] : null;
          final cats = [for (final x in (f['categories'] as List? ?? [])) asMap(x)];
          final svcs = [for (final x in (f['services'] as List? ?? [])) asMap(x)];
          final areas = [for (final a in (f['areas'] as List? ?? [])) asMap(a)];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            AppCard(
              child: Column(children: [
                Avatar(fileId: f['photo_file_id'] as String?, name: who(f), size: 84),
                const SizedBox(height: 10),
                Text(who(f), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(tr(f['fundi_type'] == 'company' ? 'pref_company' : 'pref_technician'), style: TextStyle(color: cs.secondary)),
                if (r != null) Padding(padding: const EdgeInsets.only(top: 6), child: Stars((r as num).toDouble(), size: 22)),
                const SizedBox(height: 6),
                Text('${tr('jobs_done')}: ${f['completed'] ?? 0}', style: TextStyle(color: cs.secondary)),
              ]),
            ),
            if ((f['experience'] ?? '').toString().isNotEmpty)
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('experience'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(f['experience'].toString(), style: const TextStyle(height: 1.45)),
              ])),
            if (cats.isNotEmpty || svcs.isNotEmpty)
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('services'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final x in cats) Chip(label: Text(x['name'].toString()), backgroundColor: brandSky.withOpacity(.15), visualDensity: VisualDensity.compact),
                  for (final x in svcs) Chip(label: Text(x['name'].toString()), visualDensity: VisualDensity.compact),
                ]),
              ])),
            if (areas.isNotEmpty)
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('areas_served'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final a in areas) Text('- ${[a['ward_name'], a['district_name'], a['region_name']].whereType<String>().join(', ')}'),
              ])),
            const SizedBox(height: 8),
            PillButton(tr('request_this_fundi'), icon: Icons.bolt, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportFlow(fundi: f)))),
          ]);
        },
      ),
    );
  }
}

// ===================================================================== requests
class MyRequestsPage extends StatelessWidget {
  const MyRequestsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('requests'))),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/jobs')),
        every: const Duration(seconds: 20),
        builder: (c, jobs, reload) => jobs.isEmpty
            ? EmptyView(tr('no_requests_yet'), icon: Icons.receipt_long_outlined)
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: jobs.length, itemBuilder: (_, i) => JobCard(jobs[i])),
              ),
      ),
    );
  }
}

// ===================================================================== "My Fundi"
/// Fundis / Companies the client has worked with: full details, jobs, and their BOQs.
class MyFundisPage extends StatelessWidget {
  const MyFundisPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('my_fundi'))),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/jobs/my-fundis')),
        builder: (c, list, reload) => list.isEmpty
            ? EmptyView(tr('no_my_fundi'), icon: Icons.engineering_outlined)
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: list.length,
                  itemBuilder: (_, i) {
                    final f = list[i];
                    final r = f['rating'] is Map ? (f['rating'] as Map)['avg'] : null;
                    return AppCard(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyFundiDetailPage(f: f))),
                      child: Row(children: [
                        Avatar(fileId: f['photo_file_id'] as String?, name: who(f), size: 52),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(who(f), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text((f['phone'] ?? '').toString(), style: TextStyle(color: cs.secondary)),
                          Row(children: [if (r != null) ...[Stars((r as num).toDouble(), size: 15), const SizedBox(width: 8)], Text('${f['jobs']} ${tr('requests').toLowerCase()}', style: TextStyle(color: cs.secondary, fontSize: 12.5))]),
                        ])),
                        const Icon(Icons.chevron_right),
                      ]),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class MyFundiDetailPage extends StatelessWidget {
  final J f;
  const MyFundiDetailPage({super.key, required this.f});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = f['rating'] is Map ? (f['rating'] as Map)['avg'] : null;
    return Scaffold(
      appBar: AppBar(title: Text(who(f))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/jobs/my-fundis/${f['id']}')),
        builder: (c, d, reload) {
          final jobs = asList(d['jobs']);
          final boqs = asList(d['boqs']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(fileId: f['photo_file_id'] as String?, name: who(f), size: 60),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(who(f), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(tr(f['fundi_type'] == 'company' ? 'pref_company' : 'pref_technician'), style: TextStyle(color: cs.secondary)),
                    if (r != null) Stars((r as num).toDouble()),
                  ])),
                ]),
                const SizedBox(height: 10),
                RowInfo(tr('phone'), (f['phone'] ?? '').toString()),
                if ((f['services'] ?? '').toString().isNotEmpty) RowInfo(tr('services'), f['services'].toString()),
                if ((f['experience'] ?? '').toString().isNotEmpty) RowInfo(tr('experience'), f['experience'].toString()),
                const SizedBox(height: 10),
                ContactRow((f['phone'] ?? '').toString()),
              ])),
              if (boqs.isNotEmpty) ...[
                SectionTitle(tr('boq')),
                for (final b in boqs)
                  AppCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BoqPage(boqId: b['id'] as String))),
                    child: Row(children: [
                      const Icon(Icons.table_chart_outlined),
                      const SizedBox(width: 12),
                      Expanded(child: Text((b['title'] ?? 'BOQ').toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(money(b['total'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ],
              SectionTitle(tr('requests')),
              for (final j in jobs) JobCard(j),
            ]),
          );
        },
      ),
    );
  }
}

// ===================================================================== report a problem
/// Category -> services (several allowed, plus "other") -> description (optional) -> area -> review.
/// With [fundi] the request goes to that Fundi (and the Admin); without, to every matching Fundi (and the Admin).
class ReportFlow extends StatefulWidget {
  final int? categoryId;
  final J? fundi;
  const ReportFlow({super.key, this.categoryId, this.fundi});
  @override
  State<ReportFlow> createState() => _ReportFlowState();
}

class _ReportFlowState extends State<ReportFlow> {
  final _page = PageController();
  int step = 0;
  int? categoryId;
  final Set<int> serviceIds = {};
  final _other = TextEditingController();
  String pref = 'any';
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
    categoryId = widget.categoryId;
    if (categoryId == null && widget.fundi != null) {
      final cats = widget.fundi!['categories'] as List? ?? [];
      if (cats.isNotEmpty) categoryId = (cats.first as Map)['id'] as int?;
    }
    if (categoryId == null && s.categories.length == 1) categoryId = s.categories.first['id'] as int;
    if (u['district_id'] != null) {
      loc = {'region_id': u['region_id'], 'district_id': u['district_id'], 'ward_id': u['ward_id'], 'ward_text': null, 'label': s.locLabel, 'active': true};
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _other.dispose();
    _desc.dispose();
    _landmark.dispose();
    super.dispose();
  }

  bool get _valid {
    switch (step) {
      case 0:
        return categoryId != null && (serviceIds.isNotEmpty || _other.text.trim().isNotEmpty);
      case 2:
        return loc != null && lat != null;
      default:
        return true; // the description is optional
    }
  }

  void _go(int to) {
    setState(() => step = to);
    _page.animateToPage(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _gps() async {
    final p = await busyVal(context, getPosition);
    if (p != null) {
      setState(() {
        lat = p.latitude;
        lng = p.longitude;
      });
    }
  }

  Future<void> _submit() async {
    final res = await busyVal<J>(context, () async {
      final ids = <String>[];
      for (final p in photos) {
        ids.add((await Api.upload(p))['id'] as String);
      }
      return asMap(await Api.post('/jobs', {
        'category_id': categoryId, 'service_ids': serviceIds.toList(), 'other_service': _other.text.trim(),
        'preference': pref, 'description': _desc.text.trim(), 'address': _landmark.text.trim(),
        'region_id': loc!['region_id'], 'district_id': loc!['district_id'], 'ward_id': loc!['ward_id'], 'ward_text': loc!['ward_text'],
        'lat': lat, 'lng': lng, 'photo_ids': ids,
        if (widget.fundi != null) 'fundi_id': widget.fundi!['id'],
      }));
    });
    if (res != null && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReportSuccess(job: res)));
  }

  bool _isImage(String p) {
    final e = p.toLowerCase();
    return e.endsWith('.jpg') || e.endsWith('.jpeg') || e.endsWith('.png') || e.endsWith('.webp') || e.endsWith('.heic');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final titles = [tr('step_service'), tr('step_describe'), tr('step_location'), tr('step_review')];
    // services of the chosen category (when a Fundi was chosen: only the services that Fundi offers, if any are set)
    var catServices = [for (final sv in s.services) if (categoryId == null || sv['category_id'] == categoryId) sv];
    if (widget.fundi != null) {
      final own = {for (final x in (widget.fundi!['services'] as List? ?? [])) (x as Map)['id']};
      final f = [for (final sv in catServices) if (own.contains(sv['id'])) sv];
      if (f.isNotEmpty) catServices = f;
    }
    final cats = widget.fundi != null && (widget.fundi!['categories'] as List? ?? []).isNotEmpty
        ? [for (final c in s.categories) if ((widget.fundi!['categories'] as List).any((x) => (x as Map)['id'] == c['id'])) c]
        : s.categories;
    return Scaffold(
      appBar: AppBar(title: Text(tr('report_problem')), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => step == 0 ? Navigator.pop(context) : _go(step - 1))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [for (var i = 0; i < 4; i++) Expanded(child: Container(height: 5, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: i <= step ? brandOrange : cs.outline, borderRadius: BorderRadius.circular(3))))]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(titles[step], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)))),
        if (widget.fundi != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(children: [
              Avatar(fileId: widget.fundi!['photo_file_id'] as String?, name: who(widget.fundi), size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text('${tr('chosen_fundi')}: ${who(widget.fundi)}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700))),
            ]),
          ),
        Expanded(
          child: PageView(controller: _page, physics: const NeverScrollableScrollPhysics(), children: [
            // 1. category and services (several allowed) + other service
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              if (cats.length > 1) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in cats)
                    ChoiceChip(
                      avatar: Icon(catIcon(c), size: 18), label: Text(catName(c)), selected: categoryId == c['id'],
                      onSelected: (_) => setState(() {
                        categoryId = c['id'] as int;
                        serviceIds.clear();
                      }),
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              if (categoryId == null) Text(tr('choose_category'), style: TextStyle(color: cs.secondary)),
              Text(tr('select_services_hint'), style: TextStyle(color: cs.secondary, fontSize: 13)),
              const SizedBox(height: 8),
              for (final sv in catServices)
                AppCard(
                  onTap: () => setState(() => serviceIds.contains(sv['id']) ? serviceIds.remove(sv['id']) : serviceIds.add(sv['id'] as int)),
                  color: serviceIds.contains(sv['id']) ? cs.primary.withOpacity(.1) : null,
                  child: Row(children: [
                    Expanded(child: Text(svcName(sv), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Icon(serviceIds.contains(sv['id']) ? Icons.check_box : Icons.check_box_outline_blank, color: cs.primary),
                  ]),
                ),
              const SizedBox(height: 4),
              Text(tr('other_service'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TextField(controller: _other, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: tr('other_service_hint'))),
              if (widget.fundi == null) ...[
                const SizedBox(height: 16),
                Text(tr('who_do_you_prefer'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 'any', label: Text(tr('pref_any'))), ButtonSegment(value: 'technician', label: Text(tr('pref_technician'))), ButtonSegment(value: 'company', label: Text(tr('pref_company')))],
                  selected: {pref},
                  onSelectionChanged: (v) => setState(() => pref = v.first),
                  style: const ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder()), minimumSize: WidgetStatePropertyAll(Size(0, 48))),
                ),
              ],
            ]),
            // 2. describe (optional) + pictures or any file
            ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              TextField(controller: _desc, maxLines: 5, minLines: 4, decoration: InputDecoration(hintText: tr('describe_hint_optional'))),
              const SizedBox(height: 16),
              Text(tr('photos_optional'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in photos)
                  Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _isImage(p)
                          ? Image.file(File(p), width: 84, height: 84, fit: BoxFit.cover, cacheWidth: 200)
                          : Container(width: 84, height: 84, color: cs.surfaceContainerHighest, child: const Icon(Icons.insert_drive_file_outlined)),
                    ),
                    Positioned(right: -6, top: -6, child: GestureDetector(onTap: () => setState(() => photos.remove(p)), child: CircleAvatar(radius: 12, backgroundColor: cs.error, child: const Icon(Icons.close, size: 14, color: Colors.white)))),
                  ]),
                if (photos.length < 5)
                  GestureDetector(
                    onTap: () async {
                      final r = await pickAnyAttachment(context);
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
                  final v = await pickLocation(context, requireActive: true);
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
                  RowInfo(tr('services'), [...s.services.where((x) => serviceIds.contains(x['id'])).map(svcName), if (_other.text.trim().isNotEmpty) _other.text.trim()].join(', ')),
                  if (widget.fundi != null) RowInfo(tr('fundi'), who(widget.fundi)) else RowInfo(tr('prefers'), tr(pref == 'company' ? 'pref_company' : (pref == 'technician' ? 'pref_technician' : 'pref_any'))),
                  RowInfo(tr('area'), ((loc?['label'] ?? '') as String)),
                  RowInfo(tr('gps'), lat == null ? '-' : tr('location_shared')),
                  RowInfo(tr('photos'), '${photos.length}'),
                  if (_desc.text.trim().isNotEmpty) ...[
                    const Divider(height: 20),
                    Align(alignment: Alignment.centerLeft, child: Text(_desc.text.trim(), style: const TextStyle(height: 1.4))),
                  ],
                ]),
              ),
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr(widget.fundi != null ? 'goes_to_chosen' : 'goes_to_all'), style: TextStyle(color: cs.secondary, height: 1.4))),
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
