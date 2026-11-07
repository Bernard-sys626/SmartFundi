import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'shared.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return Scaffold(
      body: IndexedStack(index: idx, children: const [_Dashboard(), _FundisPage(), _AdminJobs(), _PaymentsPage(), _MorePage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: tr('dashboard')),
          NavigationDestination(icon: const Icon(Icons.engineering_outlined), selectedIcon: const Icon(Icons.engineering), label: tr('fundis')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: tr('requests')),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments), label: tr('payments')),
          NavigationDestination(icon: const Icon(Icons.more_horiz), selectedIcon: const Icon(Icons.more_horiz), label: tr('more')),
        ],
      ),
    );
  }
}

// ===================================================================== dashboard
class _Dashboard extends StatelessWidget {
  const _Dashboard();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String label, String value, {IconData? icon}) => Expanded(
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (icon != null) Icon(icon, color: cs.primary),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: cs.secondary, fontSize: 12.5)),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('dashboard')), actions: const [BellButton()]),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/admin/dashboard')),
        every: const Duration(seconds: 30),
        builder: (c, d, reload) {
          int jobs(String s) => (asList(d['jobs_by_status']).where((x) => x['status'] == s).map((x) => x['n'] as int).fold<int>(0, (a, b) => a + b));
          int fundis(String s) => (asList(d['fundis_by_status']).where((x) => x['s'] == s).map((x) => x['n'] as int).fold<int>(0, (a, b) => a + b));
          final pay = asMap(d['payments']);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(28)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('platform_commission'), style: TextStyle(color: cs.onPrimary.withOpacity(.8))),
                  const SizedBox(height: 4),
                  Text(money(num.parse('${pay['platform']}')), style: TextStyle(color: cs.onPrimary, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('${tr('total_collected')}: ${money(num.parse('${pay['total']}'))}', style: TextStyle(color: cs.onPrimary.withOpacity(.8), fontSize: 12.5)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                stat(tr('applications'), '${fundis('pending')}', icon: Icons.assignment_ind_outlined),
                stat(tr('approved_fundis'), '${fundis('approved')}', icon: Icons.verified_outlined),
              ]),
              Row(children: [
                stat(tr('clients'), '${d['clients']}', icon: Icons.people_outline),
                stat(tr('pending_payments'), '${d['pending_payments']}', icon: Icons.hourglass_bottom),
              ]),
              SectionTitle(tr('requests')),
              Row(children: [stat(tr('st_pending'), '${jobs('pending')}'), stat(tr('st_in_progress'), '${jobs('in_progress') + jobs('accepted') + jobs('on_the_way') + jobs('arrived')}')]),
              Row(children: [stat(tr('st_completed'), '${jobs('completed')}'), stat(tr('st_cancelled'), '${jobs('cancelled')}')]),
            ]),
          );
        },
      ),
    );
  }
}

// ===================================================================== fundis
class _FundisPage extends StatefulWidget {
  const _FundisPage();
  @override
  State<_FundisPage> createState() => _FundisPageState();
}

class _FundisPageState extends State<_FundisPage> {
  String? filter = 'pending';
  int rev = 0;
  @override
  Widget build(BuildContext context) {
    final filters = <String?>['pending', 'approved', 'rejected', 'suspended', null];
    return Scaffold(
      appBar: AppBar(title: Text(tr('fundis'))),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(tr('add_fundi')),
        onPressed: () async {
          final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _AddFundiPage()));
          if (ok == true) setState(() => rev++);
        },
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final f in filters)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: ChoiceChip(shape: const StadiumBorder(), label: Text(f == null ? tr('all') : tr('st_$f')), selected: filter == f, onSelected: (_) => setState(() => filter = f))),
          ]),
        ),
        Expanded(
          child: Loader<List<J>>(
            key: ValueKey('$filter$rev'),
            load: () async => asList(await Api.get('/admin/fundis${filter == null ? '' : '?status=$filter'}')),
            builder: (c, list, reload) => list.isEmpty
                ? EmptyView(tr('nothing_here'), icon: Icons.engineering_outlined)
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                      for (final f in list)
                        AppCard(
                          onTap: () async {
                            await Navigator.push(c, MaterialPageRoute(builder: (_) => _FundiDetail(id: f['id'] as String)));
                            reload();
                          },
                          child: Row(children: [
                            Avatar(name: who(f)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(who(f), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${tr(f['fundi_type'] == 'company' ? 'type_company' : 'type_technician')}  |  ${f['districts'] ?? '-'}', style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12.5)),
                            ])),
                            StatusChip((f['fundi_status'] ?? 'incomplete') as String),
                          ]),
                        ),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _FundiDetail extends StatelessWidget {
  final String id;
  const _FundiDetail({required this.id});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('fundi'))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/admin/fundis/$id')),
        builder: (c, p, reload) {
          final u = asMap(p['user']);
          final docs = asList(p['documents']);
          final areas = asList(p['areas']);
          final names = [for (final sv in s.services) if ((p['service_ids'] as List).contains(sv['id'])) svcName(sv)];
          Future<void> act(String path, [Map<String, dynamic>? body]) async {
            if (await busy(c, () async => await Api.post('/admin/fundis/$id/$path', body ?? {}))) await reload();
          }

          final st = u['fundi_status'] as String?;
          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(fileId: u['photo_file_id'] as String?, name: who(u), size: 60),
                  const SizedBox(width: 14),
                  Expanded(child: Text(who(u), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  StatusChip(st ?? 'incomplete'),
                ]),
                const Divider(height: 24),
                RowInfo(tr('type'), tr(u['fundi_type'] == 'company' ? 'type_company' : 'type_technician')),
                RowInfo(tr('full_name'), (u['name'] ?? '-').toString()),
                if (u['fundi_type'] == 'company') RowInfo(tr('company_name'), (u['company_name'] ?? '-').toString()),
                RowInfo(tr('phone'), (u['phone'] ?? '-').toString()),
                RowInfo('Email', (u['email'] ?? '-').toString()),
                RowInfo(tr('work_areas'), [for (final a in areas) [a['ward_name'], a['district_name']].whereType<String>().join(', ')].join(' | ')),
                RowInfo(tr('services_you_offer'), names.join(', ')),
                if ((u['reject_reason'] ?? '').toString().isNotEmpty) RowInfo(tr('reason'), u['reject_reason'].toString()),
                if (u['phone'] != null) ...[const SizedBox(height: 10), ContactRow(u['phone'].toString())],
              ]),
            ),
            SectionTitle(tr('documents')),
            if (docs.isEmpty) EmptyView(tr('no_documents'), icon: Icons.folder_open_outlined),
            for (final d in docs)
              AppCard(
                onTap: () => openUri(c, Api.fileUri(d['file_id'] as String)),
                child: Row(children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('doc_${d['kind']}'), style: const TextStyle(fontWeight: FontWeight.w800)), Text('${d['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)])),
                  Icon(Icons.open_in_new, color: cs.primary, size: 18),
                ]),
              ),
            if (u['photo_file_id'] != null) AppCard(onTap: () => showPhoto(c, u['photo_file_id'] as String), child: Row(children: [const Icon(Icons.image_outlined), const SizedBox(width: 12), Text(tr(u['fundi_type'] == 'company' ? 'company_logo' : 'profile_photo'), style: const TextStyle(fontWeight: FontWeight.w800))])),
            const SizedBox(height: 8),
            if (st != 'approved') PillButton(tr('approve'), icon: Icons.check_circle_outline, onPressed: () => act('approve')),
            const SizedBox(height: 10),
            if (st != 'rejected') PillButton(tr('reject'), outlined: true, danger: true, onPressed: () async {
              final r = await inputSheet(c, title: tr('reject'), label: tr('reason'), action: tr('reject'));
              if (r != null && c.mounted) act('reject', {'reason': r});
            }),
            const SizedBox(height: 10),
            if (st == 'approved') PillButton(tr('suspend'), outlined: true, danger: true, onPressed: () async {
              if (await confirmDialog(c, tr('suspend'), tr('suspend_confirm'), danger: true) && c.mounted) act('suspend');
            }),
            const SizedBox(height: 10),
            PillButton(tr('edit_details'), outlined: true, icon: Icons.edit_outlined, onPressed: () async {
              final isCo = u['fundi_type'] == 'company';
              final v = await inputSheet(c, title: tr(isCo ? 'company_name' : 'full_name'), initial: ((isCo ? u['company_name'] : u['name']) ?? '').toString());
              if (v == null || v.isEmpty || !c.mounted) return;
              if (await busy(c, () async => await Api.put('/admin/fundis/$id', isCo ? {'company_name': v} : {'name': v}))) await reload();
            }),
          ]);
        },
      ),
    );
  }
}

/// Admin registers a Fundi or Company manually, using popups.
class _AddFundiPage extends StatefulWidget {
  const _AddFundiPage();
  @override
  State<_AddFundiPage> createState() => _AddFundiState();
}

class _AddFundiState extends State<_AddFundiPage> {
  String type = 'technician';
  String name = '', company = '', identifier = '';
  final List<J> areas = [];
  Set<int> services = {};

  Future<void> _save() async {
    if (identifier.isEmpty || (type == 'company' ? company.isEmpty : name.isEmpty) || areas.isEmpty || services.isEmpty) return toast(context, tr('err_missing_info'));
    final ok = await busy(context, () async => await Api.post('/admin/fundis', {
          'identifier': identifier, 'fundi_type': type, 'name': name, 'company_name': company, 'service_ids': services.toList(),
          'areas': [for (final a in areas) {'region_id': a['region_id'], 'district_id': a['district_id'], 'ward_id': a['ward_id']}],
        }));
    if (ok && mounted) {
      toast(context, tr('saved'));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    Widget row(IconData i, String t, String v, VoidCallback f) => AppCard(
          onTap: f,
          child: Row(children: [
            Icon(i, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w800)), Text(v.isEmpty ? tr('tap_to_set') : v, style: TextStyle(color: cs.secondary))])),
            const Icon(Icons.chevron_right),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('add_fundi'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        row(Icons.groups_outlined, tr('account_type'), tr(type == 'company' ? 'type_company' : 'type_technician'), () async {
          final v = await pickSheet<String>(context, tr('account_type'), [('technician', tr('type_technician')), ('company', tr('type_company'))]);
          if (v != null) setState(() => type = v);
        }),
        if (type == 'company') row(Icons.business_outlined, tr('company_name'), company, () async {
          final v = await inputSheet(context, title: tr('company_name'), initial: company);
          if (v != null) setState(() => company = v);
        }),
        row(Icons.badge_outlined, tr('full_name'), name, () async {
          final v = await inputSheet(context, title: tr('full_name'), initial: name);
          if (v != null) setState(() => name = v);
        }),
        row(Icons.phone_outlined, tr('phone_or_email'), identifier, () async {
          final v = await inputSheet(context, title: tr('phone_or_email'), initial: identifier, type: TextInputType.emailAddress);
          if (v != null) setState(() => identifier = v);
        }),
        row(Icons.location_on_outlined, tr('work_areas'), areas.map((a) => a['label']).join(' | '), () async {
          final v = await pickLocation(context, wholeDistrict: true);
          if (v != null) setState(() => areas.add(v));
        }),
        if (areas.isNotEmpty) Wrap(spacing: 8, children: [for (final a in areas) InputChip(label: Text('${a['label']}'), shape: const StadiumBorder(), onDeleted: () => setState(() => areas.remove(a)))]),
        row(Icons.electrical_services, tr('services_you_offer'), [for (final sv in s.services) if (services.contains(sv['id'])) svcName(sv)].join(', '), () async {
          final r = await multiPickSheet(context, tr('services_you_offer'), [for (final sv in s.services) (sv['id'] as int, svcName(sv))], services);
          if (r != null) setState(() => services = r);
        }),
        const SizedBox(height: 12),
        PillButton(tr('save'), onPressed: _save),
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr('admin_add_hint'), style: TextStyle(color: cs.secondary, fontSize: 12.5))),
      ]),
    );
  }
}

// ===================================================================== jobs
class _AdminJobs extends StatefulWidget {
  const _AdminJobs();
  @override
  State<_AdminJobs> createState() => _AdminJobsState();
}

class _AdminJobsState extends State<_AdminJobs> {
  String? filter;
  @override
  Widget build(BuildContext context) {
    final filters = <String?>[null, 'pending', 'accepted', 'on_the_way', 'arrived', 'in_progress', 'completed', 'cancelled'];
    return Scaffold(
      appBar: AppBar(title: Text(tr('requests'))),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final f in filters)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: ChoiceChip(shape: const StadiumBorder(), label: Text(f == null ? tr('all') : tr('st_$f')), selected: filter == f, onSelected: (_) => setState(() => filter = f))),
          ]),
        ),
        Expanded(
          child: Loader<List<J>>(
            key: ValueKey(filter),
            load: () async => asList(await Api.get('/admin/jobs${filter == null ? '' : '?status=$filter'}')),
            every: const Duration(seconds: 20),
            builder: (c, list, reload) => list.isEmpty
                ? EmptyView(tr('no_requests_yet'), icon: Icons.receipt_long_outlined)
                : RefreshIndicator(onRefresh: reload, child: ListView(padding: const EdgeInsets.all(16), children: [for (final j in list) JobCard(j)])),
          ),
        ),
      ]),
    );
  }
}

// ===================================================================== payments
class _PaymentsPage extends StatelessWidget {
  const _PaymentsPage();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('payments'))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/admin/payments')),
        every: const Duration(seconds: 30),
        builder: (c, d, reload) {
          final items = asList(d['items']);
          final t = asMap(d['totals']);
          Future<void> act(String id, String what) async {
            if (await busy(c, () async => await Api.post('/admin/payments/$id/$what'))) await reload();
          }

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(child: Column(children: [
                RowInfo(tr('total_collected'), money(num.parse('${t['total']}')), bold: true),
                RowInfo(tr('platform_commission'), money(num.parse('${t['platform']}'))),
                RowInfo(tr('paid_to_fundis'), money(num.parse('${t['fundi']}'))),
              ])),
              if (items.isEmpty) EmptyView(tr('no_payments_yet'), icon: Icons.payments_outlined),
              for (final p in items)
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(money(num.parse('${p['amount']}')), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                      StatusChip(p['status'] as String),
                    ]),
                    const SizedBox(height: 4),
                    Text('${p['code']}  |  ${tr('pm_${p['method']}')}  |  ${fmtDate(p['created_at'])}', style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                    Text('${p['client_name'] ?? '-'}  >  ${p['fundi_name'] ?? '-'}', style: const TextStyle(fontSize: 13)),
                    if ((p['reference'] ?? '').toString().isNotEmpty) Text('${tr('reference')}: ${p['reference']}${(p['phone'] ?? '').toString().isEmpty ? '' : '  |  ${p['phone']}'}', style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                    if (p['status'] == 'success') Text('${tr('platform_commission')}: ${money(num.parse('${p['platform_amount']}'))}  (${p['commission_percent']}%)', style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                    if (p['status'] == 'pending') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: PillButton(tr('confirm'), onPressed: () => act(p['id'] as String, 'confirm'))),
                        const SizedBox(width: 10),
                        Expanded(child: PillButton(tr('reject'), outlined: true, danger: true, onPressed: () => act(p['id'] as String, 'reject'))),
                      ]),
                    ],
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ===================================================================== more
class _MorePage extends StatelessWidget {
  const _MorePage();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final main = s.user!['is_main_admin'] == true;
    Widget tile(IconData i, String t, Widget page) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(i), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page))),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('more')), actions: const [BellButton()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(child: Row(children: [
          const LogoMark(44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name.isEmpty ? 'Admin' : s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(tr(main ? 'main_admin' : 'regional_admin'), style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ])),
        ])),
        tile(Icons.map_outlined, tr('locations'), const _LocationsPage()),
        tile(Icons.electrical_services, tr('services'), const _ServicesPage()),
        tile(Icons.percent, tr('commission_payments'), const _CommissionPage()),
        if (main) tile(Icons.admin_panel_settings_outlined, tr('admins'), const _AdminsPage()),
        tile(Icons.settings_outlined, tr('settings'), const SettingsPage()),
      ]),
    );
  }
}

// ----- services
class _ServicesPage extends StatefulWidget {
  const _ServicesPage();
  @override
  State<_ServicesPage> createState() => _ServicesState();
}

class _ServicesState extends State<_ServicesPage> {
  int rev = 0;
  Future<void> _edit([J? sv]) async {
    final c = context;
    final sw = await inputSheet(c, title: '${tr('service_name')} (Kiswahili)', initial: (sv?['name_sw'] ?? '').toString());
    if (sw == null || sw.isEmpty || !c.mounted) return;
    final en = await inputSheet(c, title: '${tr('service_name')} (English)', initial: (sv?['name_en'] ?? '').toString());
    if (en == null || !c.mounted) return;
    final fr = await inputSheet(c, title: '${tr('service_name')} (Français)', initial: (sv?['name_fr'] ?? '').toString());
    if (fr == null || !c.mounted) return;
    final body = {'name_sw': sw, 'name_en': en.isEmpty ? sw : en, 'name_fr': fr.isEmpty ? (en.isEmpty ? sw : en) : fr};
    if (await busy(c, () async => sv == null ? await Api.post('/admin/services', body) : await Api.put('/admin/services/${sv['id']}', body))) setState(() => rev++);
  }

  @override
  Widget build(BuildContext context) {
    final isMain = context.read<AppState>().user!['is_main_admin'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('services'))),
      floatingActionButton: isMain ? FloatingActionButton.extended(shape: const StadiumBorder(), onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(tr('add_service'))) : null,
      body: Loader<List<J>>(
        key: ValueKey(rev),
        load: () async => asList(await Api.get('/admin/services')),
        builder: (c, list, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(tr('services_hint'), style: TextStyle(color: Theme.of(c).colorScheme.secondary))),
          for (final sv in list)
            AppCard(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((sv['name_$currentLang'] ?? sv['name_en']).toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${sv['trade']}', style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12)),
                ])),
                if (isMain) ...[
                  Switch(value: sv['active'] == true, onChanged: (v) async {
                    if (await busy(c, () async => await Api.put('/admin/services/${sv['id']}', {'active': v}))) setState(() => rev++);
                  }),
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(sv)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await confirmDialog(c, tr('delete'), tr('delete_service_confirm'), danger: true)) return;
                      if (c.mounted && await busy(c, () async => await Api.delete('/admin/services/${sv['id']}'))) setState(() => rev++);
                    },
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

// ----- commission and payment methods
class _CommissionPage extends StatefulWidget {
  const _CommissionPage();
  @override
  State<_CommissionPage> createState() => _CommissionState();
}

class _CommissionState extends State<_CommissionPage> {
  int rev = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final isMain = app.user!['is_main_admin'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('commission_payments'))),
      body: Loader<J>(
        key: ValueKey(rev),
        load: () async => asMap(await Api.get('/admin/settings')),
        builder: (c, st, reload) {
          final pm = asMap(st['payment_methods']);
          Future<void> save(Map<String, dynamic> body) async {
            if (await busy(c, () async => await Api.put('/admin/settings', body))) {
              await app.loadConfig();
              setState(() => rev++);
            }
          }

          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              onTap: !isMain ? null : () async {
                final v = await inputSheet(c, title: tr('commission_percent'), initial: '${st['commission_percent']}', type: TextInputType.number);
                final n = num.tryParse(v ?? '');
                if (n == null) return;
                save({'commission_percent': n});
              },
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('commission_percent'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(tr('commission_hint'), style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12.5)),
                ])),
                Text('${st['commission_percent']}%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ]),
            ),
            SectionTitle(tr('payment_methods')),
            for (final k in ['mobile_money', 'bank', 'lipa_namba'])
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('pm_$k'), style: const TextStyle(fontWeight: FontWeight.w700)), value: pm[k] == true, onChanged: !isMain ? null : (v) => save({'payment_methods': {...pm, k: v}})),
              ),
            if (!isMain) Text(tr('main_admin_only'), style: TextStyle(color: Theme.of(c).colorScheme.secondary)),
          ]);
        },
      ),
    );
  }
}

// ----- locations / coverage
class _LocationsPage extends StatefulWidget {
  const _LocationsPage();
  @override
  State<_LocationsPage> createState() => _LocationsState();
}

class _LocationsState extends State<_LocationsPage> {
  int rev = 0;
  Future<void> _import() async {
    final t = await inputSheet(context, title: tr('import_locations'), label: tr('import_hint'), maxLines: 8, action: tr('import'));
    if (t == null || t.isEmpty || !mounted) return;
    final rows = <Map<String, String>>[];
    for (final line in t.split('\n')) {
      final p = line.split(',').map((e) => e.trim()).toList();
      if (p.length >= 2 && p[0].isNotEmpty && p[1].isNotEmpty) rows.add({'region': p[0], 'district': p[1], if (p.length > 2 && p[2].isNotEmpty) 'ward': p[2]});
    }
    if (rows.isEmpty) return toast(context, tr('err_generic'));
    J? res;
    final ok = await busy(context, () async => res = asMap(await Api.post('/admin/locations/import', {'rows': rows})));
    if (ok && mounted) {
      toast(context, '${tr('imported')}: ${res!['imported']}');
      setState(() => rev++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMain = context.read<AppState>().user!['is_main_admin'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('locations')), actions: [if (isMain) IconButton(icon: const Icon(Icons.upload_file), onPressed: _import)]),
      body: Loader<List<J>>(
        key: ValueKey(rev),
        load: () async => asList(await Api.get('/admin/coverage')),
        builder: (c, regions, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(tr('coverage_hint'), style: TextStyle(color: Theme.of(c).colorScheme.secondary))),
            for (final r in regions)
              AppCard(
                onTap: () async {
                  await Navigator.push(c, MaterialPageRoute(builder: (_) => _RegionPage(region: r)));
                  setState(() => rev++);
                },
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${r['districts']} ${tr('districts')}  |  ${r['fundis']} ${tr('fundis')}', style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12.5)),
                  ])),
                  Switch(value: r['active'] == true, onChanged: (v) async {
                    if (await busy(c, () async => await Api.put('/admin/regions/${r['id']}', {'active': v}))) setState(() => rev++);
                  }),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _RegionPage extends StatefulWidget {
  final J region;
  const _RegionPage({required this.region});
  @override
  State<_RegionPage> createState() => _RegionState();
}

class _RegionState extends State<_RegionPage> {
  int rev = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.region['name'] as String)),
      floatingActionButton: FloatingActionButton.extended(
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add),
        label: Text(tr('add_district')),
        onPressed: () async {
          final v = await inputSheet(context, title: tr('add_district'), label: tr('district'));
          if (v == null || v.isEmpty || !mounted) return;
          if (await busy(context, () async => await Api.post('/admin/districts', {'region_id': widget.region['id'], 'name': v}))) setState(() => rev++);
        },
      ),
      body: Loader<List<J>>(
        key: ValueKey(rev),
        load: () async => asList(await Api.get('/admin/coverage/${widget.region['id']}')),
        builder: (c, ds, reload) => ds.isEmpty
            ? EmptyView(tr('no_districts'), icon: Icons.map_outlined)
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                for (final d in ds)
                  AppCard(
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${d['wards']} ${tr('wards')}  |  ${d['fundis']} ${tr('fundis')}', style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12.5)),
                      ])),
                      IconButton(
                        icon: const Icon(Icons.add_location_alt_outlined),
                        onPressed: () async {
                          final v = await inputSheet(c, title: tr('add_ward'), label: tr('ward'));
                          if (v == null || v.isEmpty || !c.mounted) return;
                          if (await busy(c, () async => await Api.post('/admin/wards', {'district_id': d['id'], 'name': v}))) setState(() => rev++);
                        },
                      ),
                      Switch(value: d['active'] == true, onChanged: (v) async {
                        if (await busy(c, () async => await Api.put('/admin/districts/${d['id']}', {'active': v}))) setState(() => rev++);
                      }),
                    ]),
                  ),
              ]),
      ),
    );
  }
}

// ----- other admins
class _AdminsPage extends StatefulWidget {
  const _AdminsPage();
  @override
  State<_AdminsPage> createState() => _AdminsState();
}

class _AdminsState extends State<_AdminsPage> {
  int rev = 0;
  Future<void> _add() async {
    final c = context;
    final id = await inputSheet(c, title: tr('phone_or_email'), type: TextInputType.emailAddress);
    if (id == null || id.isEmpty || !c.mounted) return;
    final name = await inputSheet(c, title: tr('full_name'));
    if (name == null || !c.mounted) return;
    final regions = asList(await busyVal<List>(c, () async => await Api.get('/locations/regions') as List) ?? []);
    if (regions.isEmpty || !c.mounted) return;
    final sel = await multiPickSheet(c, tr('admin_regions'), [for (final r in regions) (r['id'] as int, r['name'] as String)], {});
    if (sel == null || !c.mounted) return;
    if (await busy(c, () async => await Api.post('/admin/admins', {'identifier': id, 'name': name, 'region_ids': sel.toList()}))) setState(() => rev++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('admins'))),
      floatingActionButton: FloatingActionButton.extended(shape: const StadiumBorder(), onPressed: _add, icon: const Icon(Icons.person_add_alt_1), label: Text(tr('add_admin'))),
      body: Loader<List<J>>(
        key: ValueKey(rev),
        load: () async => asList(await Api.get('/admin/admins')),
        builder: (c, list, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(tr('admins_hint'), style: TextStyle(color: Theme.of(c).colorScheme.secondary))),
          for (final a in list)
            AppCard(
              child: Row(children: [
                Avatar(name: who(a)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(who(a), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(a['is_main_admin'] == true ? tr('main_admin') : (asList(a['regions']).map((r) => r['name']).join(', ').isEmpty ? tr('no_regions') : asList(a['regions']).map((r) => r['name']).join(', ')), style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12.5)),
                ])),
                if (a['is_main_admin'] != true)
                  IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      if (!await confirmDialog(c, tr('remove'), tr('remove_admin_confirm'), danger: true)) return;
                      if (c.mounted && await busy(c, () async => await Api.delete('/admin/admins/${a['id']}'))) setState(() => rev++);
                    },
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
