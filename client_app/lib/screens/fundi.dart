import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smartfundi_core/smartfundi_core.dart';
import 'package:provider/provider.dart';

/// Decides what a Fundi/Company sees depending on the approval status.
class FundiGate extends StatelessWidget {
  const FundiGate({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>().user!['fundi_status'];
    switch (st) {
      case 'approved':
        return const FundiShell();
      case 'pending':
        return const PendingScreen();
      case 'suspended':
        return const _BlockedScreen();
      default:
        return const FundiRegistration();
    }
  }
}

const _docKinds = ['national_id', 'education', 'professional', 'company_reg', 'quotation', 'invoice', 'other'];

// ===================================================================== profile editing helpers
class _P {
  static Future<void> put(BuildContext c, Map<String, dynamic> body, Future<void> Function() reload) async {
    if (await busy(c, () async => await Api.put('/fundi/profile', body))) await reload();
  }

  static List<Map<String, dynamic>> areaPayload(J p, {J? add, int? remove}) {
    final out = <Map<String, dynamic>>[];
    for (final a in asList(p['areas'])) {
      if (remove != null && a['id'] == remove) continue;
      out.add({'region_id': a['region_id'], 'district_id': a['district_id'], 'ward_id': a['ward_id']});
    }
    if (add != null) out.add({'region_id': add['region_id'], 'district_id': add['district_id'], 'ward_id': add['ward_id']});
    return out;
  }

  static Future<void> addArea(BuildContext c, J p, Future<void> Function() reload) async {
    final v = await pickLocation(c, wholeDistrict: true);
    if (v == null || !c.mounted) return;
    await put(c, {'areas': areaPayload(p, add: v)}, reload);
  }

  static Future<void> services(BuildContext c, J p, Future<void> Function() reload) async {
    final s = c.read<AppState>();
    final cur = {for (final x in (p['service_ids'] as List)) x as int};
    final r = await multiPickSheet(c, tr('services_you_offer'), [for (final sv in s.services) (sv['id'] as int, svcName(sv))], cur);
    if (r == null || !c.mounted) return;
    await put(c, {'service_ids': r.toList()}, reload);
  }

  static Future<void> name(BuildContext c, J p, Future<void> Function() reload) async {
    final user = asMap(p['user']);
    final isCo = user['fundi_type'] == 'company';
    final v = await inputSheet(c, title: tr(isCo ? 'company_name' : 'full_name'), initial: ((isCo ? user['company_name'] : user['name']) ?? '').toString());
    if (v == null || v.isEmpty || !c.mounted) return;
    await put(c, isCo ? {'company_name': v} : {'name': v}, reload);
    if (c.mounted) c.read<AppState>().refreshMe();
  }

  static Future<void> photo(BuildContext c, Future<void> Function() reload) async {
    final r = await pickImages(c, multi: false);
    if (r.isEmpty || !c.mounted) return;
    final ok = await busy(c, () async {
      final f = await Api.upload(r.first);
      await Api.put('/fundi/profile', {'photo_file_id': f['id']});
    });
    if (ok) {
      await reload();
      if (c.mounted) c.read<AppState>().refreshMe();
    }
  }

  static Future<void> addDoc(BuildContext c, String kind, Future<void> Function() reload) async {
    final p = await pickDocument(c);
    if (p == null || !c.mounted) return;
    final ok = await busy(c, () async {
      final f = await Api.upload(p);
      await Api.post('/fundi/documents', {'kind': kind, 'file_id': f['id'], 'name': f['name']});
    });
    if (ok) await reload();
  }
}

// ===================================================================== registration wizard
class FundiRegistration extends StatelessWidget {
  const FundiRegistration({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('fundi_registration')), actions: [TextButton(onPressed: () => context.read<AppState>().logout(), child: Text(tr('logout')))]),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/fundi/profile')),
        builder: (c, p, reload) => _RegBody(p: p, reload: reload),
      ),
    );
  }
}

class _RegBody extends StatelessWidget {
  final J p;
  final Future<void> Function() reload;
  const _RegBody({required this.p, required this.reload});

  Widget _step({required BuildContext c, required IconData icon, required String title, required String value, required VoidCallback onTap, required bool done}) {
    final cs = Theme.of(c).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        CircleAvatar(backgroundColor: done ? const Color(0xFF2F855A) : cs.primary.withOpacity(.14), child: Icon(done ? Icons.check : icon, color: done ? Colors.white : cs.primary)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(value.isEmpty ? tr('tap_to_set') : value, style: TextStyle(color: cs.secondary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        const Icon(Icons.chevron_right),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final user = asMap(p['user']);
    final type = user['fundi_type'] as String?;
    final isCo = type == 'company';
    final docs = asList(p['documents']);
    bool has(String k) => docs.any((d) => d['kind'] == k);
    final areas = asList(p['areas']);
    final serviceNames = [for (final sv in s.services) if ((p['service_ids'] as List).contains(sv['id'])) svcName(sv)];

    Widget docRow(String kind, {required bool required}) {
      final mine = docs.where((d) => d['kind'] == kind).toList();
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(mine.isNotEmpty ? Icons.check_circle : Icons.circle_outlined, color: mine.isNotEmpty ? const Color(0xFF2F855A) : cs.outline),
            const SizedBox(width: 10),
            Expanded(child: Text('${tr('doc_$kind')}${required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => _P.addDoc(context, kind, reload), child: Text(tr('attach'))),
          ]),
          for (final d in mine)
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(children: [
                Expanded(child: InkWell(onTap: () => openUri(context, Api.fileUri(d['file_id'] as String)), child: Text((d['name'] ?? tr('attachment')).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.primary)))),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    if (await busy(context, () async => await Api.delete('/fundi/documents/${d['id']}'))) await reload();
                  },
                ),
              ]),
            ),
        ]),
      );
    }

    Future<void> submit() async {
      try {
        await Api.post('/fundi/submit');
        if (context.mounted) await context.read<AppState>().refreshMe();
      } on ApiError catch (e) {
        if (!context.mounted) return;
        if (e.code == 'missing_info') {
          final miss = [for (final m in (e.data['missing'] ?? []) as List) tr('miss_$m')];
          toast(context, '${tr('err_missing_info')}: ${miss.join(', ')}');
        } else {
          toast(context, errText(e));
        }
      }
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      if (user['fundi_status'] == 'rejected')
        Container(
          width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.error.withOpacity(.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.error.withOpacity(.6))),
          child: Text('${tr('application_rejected')}${(user['reject_reason'] ?? '').toString().isEmpty ? '' : '\n${user['reject_reason']}'}', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
        ),
      Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text(tr('registration_sub'), style: TextStyle(color: cs.secondary, height: 1.4))),
      _step(c: context, icon: Icons.groups_outlined, title: tr('account_type'), value: type == null ? '' : tr(isCo ? 'type_company' : 'type_technician'), done: type != null, onTap: () async {
        final v = await pickSheet<String>(context, tr('account_type'), [('technician', tr('type_technician')), ('company', tr('type_company'))]);
        if (v != null && context.mounted) await _P.put(context, {'fundi_type': v}, reload);
      }),
      if (type != null) ...[
        _step(c: context, icon: Icons.badge_outlined, title: tr(isCo ? 'company_name' : 'full_name'), value: ((isCo ? user['company_name'] : user['name']) ?? '').toString(), done: ((isCo ? user['company_name'] : user['name']) ?? '').toString().isNotEmpty, onTap: () => _P.name(context, p, reload)),
        _step(c: context, icon: Icons.location_on_outlined, title: tr('work_areas'), value: [for (final a in areas) [a['ward_name'], a['district_name']].whereType<String>().join(', ')].join(' | '), done: areas.isNotEmpty, onTap: () => _P.addArea(context, p, reload)),
        if (areas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final a in areas)
                InputChip(label: Text([a['ward_name'], a['district_name']].whereType<String>().join(', ')), shape: const StadiumBorder(), onDeleted: () => _P.put(context, {'areas': _P.areaPayload(p, remove: a['id'] as int)}, reload)),
            ]),
          ),
        _step(c: context, icon: Icons.electrical_services, title: tr('services_you_offer'), value: serviceNames.join(', '), done: serviceNames.isNotEmpty, onTap: () => _P.services(context, p, reload)),
        SectionTitle(tr('documents')),
        AppCard(
          onTap: () => _P.photo(context, reload),
          child: Row(children: [
            Avatar(fileId: user['photo_file_id'] as String?, name: (user['name'] ?? '').toString(), size: 48),
            const SizedBox(width: 14),
            Expanded(child: Text('${tr(isCo ? 'company_logo' : 'profile_photo')} *', style: const TextStyle(fontWeight: FontWeight.w700))),
            const Icon(Icons.add_a_photo_outlined),
          ]),
        ),
        if (!isCo) ...[
          docRow('national_id', required: true),
          docRow('education', required: false),
          docRow('professional', required: false),
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text(tr('certificates_hint'), style: TextStyle(color: cs.secondary, fontSize: 12.5))),
        ] else
          docRow('company_reg', required: true),
        const SizedBox(height: 8),
        PillButton(tr('submit_for_approval'), onPressed: submit),
      ],
    ]);
  }
}

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});
  @override
  State<PendingScreen> createState() => _PendingState();
}

class _PendingState extends State<PendingScreen> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => context.read<AppState>().refreshMe());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircleAvatar(radius: 44, backgroundColor: brandYellow, child: Icon(Icons.hourglass_top_rounded, size: 46, color: brandBlue)),
            const SizedBox(height: 24),
            Text(tr('pending_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(tr('pending_sub'), textAlign: TextAlign.center, style: TextStyle(color: cs.secondary, height: 1.4)),
            const SizedBox(height: 28),
            PillButton(tr('contact_support'), outlined: true, icon: Icons.support_agent, onPressed: () {
              if (s.supportPhones.isNotEmpty) openUri(context, telUri(s.supportPhones.first));
            }),
            TextButton(onPressed: s.logout, child: Text(tr('logout'))),
          ]),
        ),
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen();
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.block, size: 64),
            const SizedBox(height: 16),
            Text(tr('suspended_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(tr('suspended_sub'), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PillButton(tr('contact_support'), outlined: true, onPressed: () {
              if (s.supportPhones.isNotEmpty) openUri(context, telUri(s.supportPhones.first));
            }),
            TextButton(onPressed: s.logout, child: Text(tr('logout'))),
          ]),
        ),
      ),
    );
  }
}

// ===================================================================== approved fundi shell
class FundiShell extends StatefulWidget {
  const FundiShell({super.key});
  @override
  State<FundiShell> createState() => _FundiShellState();
}

class _FundiShellState extends State<FundiShell> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return Scaffold(
      body: IndexedStack(index: idx, children: const [_AvailablePage(), _MyJobsPage(), _EarningsPage(), _DocumentsPage(), _FundiProfilePage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.flash_on_outlined), selectedIcon: const Icon(Icons.flash_on), label: tr('available_jobs')),
          NavigationDestination(icon: const Icon(Icons.work_outline), selectedIcon: const Icon(Icons.work), label: tr('my_jobs')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: tr('earnings')),
          NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: tr('documents')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('profile')),
        ],
      ),
    );
  }
}

class _AvailablePage extends StatelessWidget {
  const _AvailablePage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('available_jobs')), actions: const [BellButton()]),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/fundi/jobs/available')),
        every: const Duration(seconds: 15),
        builder: (c, jobs, reload) => jobs.isEmpty
            ? EmptyView(tr('no_available_jobs'), icon: Icons.flash_off_outlined)
            : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.all(16), children: [for (final j in jobs) JobCard(j)])),
      ),
    );
  }
}

class _MyJobsPage extends StatelessWidget {
  const _MyJobsPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('my_jobs')), actions: const [BellButton()]),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/fundi/jobs/mine')),
        every: const Duration(seconds: 15),
        builder: (c, jobs, reload) => jobs.isEmpty
            ? EmptyView(tr('no_my_jobs'), icon: Icons.work_outline)
            : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.all(16), children: [for (final j in jobs) JobCard(j)])),
      ),
    );
  }
}

class _EarningsPage extends StatelessWidget {
  const _EarningsPage();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('earnings')), actions: const [BellButton()]),
      body: Loader<J>(
        load: () async {
          await s.loadConfig();
          return asMap(await Api.get('/fundi/earnings'));
        },
        every: const Duration(seconds: 30),
        builder: (c, e, reload) {
          final hist = asList(e['history']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(28)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('total_earned'), style: TextStyle(color: cs.onPrimary.withOpacity(.8))),
                  const SizedBox(height: 4),
                  Text(money(e['total_earned'] as num), style: TextStyle(color: cs.onPrimary, fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(tr('earn_split', {'f': '${100 - s.commission}', 'p': '${s.commission}'}), style: TextStyle(color: cs.onPrimary.withOpacity(.8), fontSize: 12.5)),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(child: Column(children: [
                RowInfo(tr('paid_by_clients'), money(e['total_paid_by_clients'] as num)),
                RowInfo(tr('platform_fees'), money(e['platform_fees'] as num)),
                RowInfo(tr('awaiting_confirmation'), money(e['pending_confirmation'] as num)),
                RowInfo(tr('outstanding'), money(e['outstanding_from_clients'] as num), bold: true),
              ])),
              SectionTitle(tr('payment_history')),
              if (hist.isEmpty) EmptyView(tr('no_payments_yet'), icon: Icons.payments_outlined),
              for (final h in hist)
                AppCard(
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${h['code']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(fmtDate(h['created_at']), style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(h['status'] == 'success' ? money(h['fundi_amount'] as num) : money(h['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      StatusChip(h['status'] as String),
                    ]),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _DocumentsPage extends StatelessWidget {
  const _DocumentsPage();
  @override
  Widget build(BuildContext context) {
    return Loader<J>(
      load: () async => asMap(await Api.get('/fundi/profile')),
      every: const Duration(seconds: 60),
      builder: (c, p, reload) {
        final docs = asList(p['documents']);
        return Scaffold(
          appBar: AppBar(title: Text(tr('documents')), actions: const [BellButton()]),
          floatingActionButton: FloatingActionButton.extended(
            shape: const StadiumBorder(),
            onPressed: () async {
              final k = await pickSheet<String>(c, tr('document_type'), [for (final k in _docKinds) (k, tr('doc_$k'))]);
              if (k != null && c.mounted) await _P.addDoc(c, k, reload);
            },
            icon: const Icon(Icons.upload_file),
            label: Text(tr('upload')),
          ),
          body: docs.isEmpty
              ? EmptyView(tr('no_documents'), icon: Icons.folder_open_outlined)
              : RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                    for (final d in docs)
                      AppCard(
                        onTap: () => openUri(c, Api.fileUri(d['file_id'] as String)),
                        child: Row(children: [
                          const Icon(Icons.description_outlined),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('doc_${d['kind']}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${d['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(fmtDate(d['created_at']), style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.secondary)),
                          ])),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!await confirmDialog(c, tr('delete'), tr('delete_doc_confirm'), danger: true)) return;
                              if (c.mounted && await busy(c, () async => await Api.delete('/fundi/documents/${d['id']}'))) await reload();
                            },
                          ),
                        ]),
                      ),
                  ]),
                ),
        );
      },
    );
  }
}

class _FundiProfilePage extends StatelessWidget {
  const _FundiProfilePage();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('profile')), actions: const [BellButton()]),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/fundi/profile')),
        builder: (c, p, reload) {
          final user = asMap(p['user']);
          final isCo = user['fundi_type'] == 'company';
          final areas = asList(p['areas']);
          final names = [for (final sv in s.services) if ((p['service_ids'] as List).contains(sv['id'])) svcName(sv)];
          Widget tile(IconData i, String t, String sub, VoidCallback f) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(i), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: sub.isEmpty ? null : Text(sub), trailing: const Icon(Icons.chevron_right), onTap: f),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            AppCard(
              child: Row(children: [
                GestureDetector(onTap: () => _P.photo(c, reload), child: Avatar(fileId: user['photo_file_id'] as String?, name: who(user), size: 64)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(who(user), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(tr(isCo ? 'type_company' : 'type_technician'), style: TextStyle(color: cs.secondary)),
                  const SizedBox(height: 6),
                  StatusChip(user['fundi_status'] as String),
                ])),
              ]),
            ),
            tile(Icons.badge_outlined, tr(isCo ? 'company_name' : 'full_name'), who(user), () => _P.name(c, p, reload)),
            tile(Icons.location_on_outlined, tr('work_areas'), [for (final a in areas) [a['ward_name'], a['district_name']].whereType<String>().join(', ')].join(' | '), () async {
              final act = await pickSheet<String>(c, tr('work_areas'), [('add', tr('add_area')), for (final a in areas) ('rm${a['id']}', '${tr('remove')}: ${[a['ward_name'], a['district_name']].whereType<String>().join(', ')}')]);
              if (act == null || !c.mounted) return;
              if (act == 'add') {
                await _P.addArea(c, p, reload);
              } else {
                await _P.put(c, {'areas': _P.areaPayload(p, remove: int.parse(act.substring(2)))}, reload);
              }
            }),
            tile(Icons.electrical_services, tr('services_you_offer'), names.join(', '), () => _P.services(c, p, reload)),
            tile(Icons.settings_outlined, tr('settings'), '', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SettingsPage()))),
          ]);
        },
      ),
    );
  }
}
