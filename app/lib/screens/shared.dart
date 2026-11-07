import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

typedef J = Map<String, dynamic>;
J asMap(dynamic v) => Map<String, dynamic>.from(v as Map);
List<J> asList(dynamic v) => [for (final e in v as List) asMap(e)];

// ===================================================================== job card
class JobCard extends StatelessWidget {
  final J job;
  const JobCard(this.job, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = [job['ward_name'], job['district_name']].whereType<String>().join(', ');
    return AppCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: job['id'] as String))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text((job['service_name'] ?? '').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          StatusChip(job['status'] as String),
        ]),
        const SizedBox(height: 6),
        Text('${job['code']}  |  ${fmtDate(job['created_at'])}', style: TextStyle(color: cs.secondary, fontSize: 12.5)),
        const SizedBox(height: 8),
        Text((job['description'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (area.isNotEmpty) ...[const SizedBox(height: 8), Row(children: [Icon(Icons.location_on_outlined, size: 16, color: cs.secondary), const SizedBox(width: 4), Expanded(child: Text(area, style: TextStyle(color: cs.secondary, fontSize: 13)))])],
        if (job['quotation'] != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text(money(job['quotation']['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            StatusChip(job['payment_status'] as String),
          ]),
        ],
      ]),
    );
  }
}

// ===================================================================== job detail
class JobDetailPage extends StatelessWidget {
  final String jobId;
  const JobDetailPage({super.key, required this.jobId});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('job_details'))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/jobs/$jobId')),
        every: const Duration(seconds: 10),
        builder: (c, j, reload) => RefreshIndicator(onRefresh: reload, child: _JobBody(job: j, reload: reload)),
      ),
    );
  }
}

const _steps = ['pending', 'accepted', 'on_the_way', 'arrived', 'in_progress', 'completed'];

class _JobBody extends StatelessWidget {
  final J job;
  final Future<void> Function() reload;
  const _JobBody({required this.job, required this.reload});

  String? _time(String s) => {
        'pending': job['created_at'], 'accepted': job['accepted_at'], 'on_the_way': job['on_the_way_at'],
        'arrived': job['arrived_at'], 'in_progress': job['started_at'], 'completed': job['completed_at'],
      }[s]?.toString();

  Future<void> _act(BuildContext c, Future<dynamic> Function() f, {String? okMsg}) async {
    final ok = await busy(c, () async => await f());
    if (ok) {
      await reload();
      if (okMsg != null && c.mounted) toast(c, okMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final role = s.role;
    final id = job['id'] as String;
    final status = job['status'] as String;
    final fundi = job['fundi'] == null ? null : asMap(job['fundi']);
    final client = job['client'] == null ? null : asMap(job['client']);
    final quote = job['quotation'] == null ? null : asMap(job['quotation']);
    final isMyFundiJob = role == 'fundi' && fundi != null && fundi['id'] == s.user!['id'];
    final open = status != 'completed' && status != 'cancelled';
    final photos = [for (final p in (job['photos'] as List)) p as String];
    final area = [job['ward_name'], job['district_name'], job['region_name']].whereType<String>().join(', ');

    final children = <Widget>[
      // header
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((job['service_name'] ?? '').toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            StatusChip(status),
          ]),
          const SizedBox(height: 6),
          Text('${job['code']}  |  ${fmtDate(job['created_at'])}', style: TextStyle(color: cs.secondary)),
          if (status == 'cancelled' && (job['cancel_reason'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), Text('${tr('reason')}: ${job['cancel_reason']}')],
        ]),
      ),
      if (job['nauli_due'] == true)
        Container(
          width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.error.withOpacity(.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.error.withOpacity(.6))),
          child: Text(tr('nauli_due_notice'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
        ),
      if (role == 'client' && ['pending', 'accepted', 'on_the_way', 'arrived'].contains(status)) const NauliNotice(compact: true),
      // timeline
      AppCard(
        child: Column(children: [
          for (var i = 0; i < _steps.length; i++)
            _TimelineRow(
              label: tr('st_${_steps[i]}'),
              time: _time(_steps[i]),
              reached: _time(_steps[i]) != null,
              last: i == _steps.length - 1,
            ),
          if (status == 'cancelled') _TimelineRow(label: tr('st_cancelled'), time: job['cancelled_at']?.toString(), reached: true, last: true, danger: true),
        ]),
      ),
      // details
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('problem'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text((job['description'] ?? '').toString(), style: const TextStyle(height: 1.4)),
          if ((job['notes'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), Text((job['notes']).toString(), style: TextStyle(color: cs.secondary))],
          const Divider(height: 24),
          RowInfo(tr('area'), area),
          RowInfo(tr('prefers'), tr(job['preference'] == 'company' ? 'pref_company' : 'pref_technician')),
          if ((job['address'] ?? '').toString().isNotEmpty) RowInfo(tr('landmark'), job['address'].toString()),
          if (job['lat'] != null) ...[
            const SizedBox(height: 8),
            PillButton(tr('open_map'), icon: Icons.map_outlined, outlined: true, onPressed: () => openUri(context, mapsUri(job['lat'] as num, job['lng'] as num))),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in photos) GestureDetector(onTap: () => showPhoto(context, p), child: FileImg(p, w: 84, h: 84)),
            ]),
          ],
        ]),
      ),
      // fundi (for client and admin)
      if (fundi != null && role != 'fundi')
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(fileId: fundi['photo_file_id'] as String?, name: who(fundi)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(who(fundi), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(tr(fundi['fundi_type'] == 'company' ? 'pref_company' : 'pref_technician'), style: TextStyle(color: cs.secondary)),
                if ((fundi['rating'] as Map)['avg'] != null)
                  Row(children: [const Icon(Icons.star_rounded, color: brandYellow, size: 18), Text(' ${(fundi['rating'] as Map)['avg']} (${(fundi['rating'] as Map)['count']})')]),
              ])),
            ]),
            if (job['can_contact'] == true) ...[
              const SizedBox(height: 12),
              ContactRow((fundi['phone'] ?? '').toString(), onChat: role == 'client' ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(jobId: id, title: who(fundi)))) : null),
            ],
          ]),
        ),
      // client (for fundi after accepting, and admin)
      if (client != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('client'), style: TextStyle(color: cs.secondary)),
            const SizedBox(height: 4),
            Text(who(client), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (job['can_contact'] == true) ...[
              const SizedBox(height: 12),
              ContactRow((client['phone'] ?? '').toString(), onChat: isMyFundiJob ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(jobId: id, title: who(client)))) : null),
            ],
          ]),
        ),
      // quotation
      if (quote != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('quotation'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            RowInfo(tr('amount_to_pay'), money(quote['amount'] as num), bold: true),
            RowInfo(tr('includes_transport'), tr(quote['includes_transport'] == true ? 'yes' : 'no')),
            if ((quote['note'] ?? '').toString().isNotEmpty) RowInfo(tr('note'), quote['note'].toString()),
            if ((quote['file_ids'] as List).isNotEmpty)
              Wrap(spacing: 8, children: [
                for (final f in quote['file_ids'] as List)
                  ActionChip(avatar: const Icon(Icons.attach_file, size: 16), label: Text(tr('attachment')), shape: const StadiumBorder(), onPressed: () => openUri(context, Api.fileUri(f as String))),
              ]),
          ]),
        ),
      // payments
      if (quote != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(tr('payment'), style: const TextStyle(fontWeight: FontWeight.w800))), StatusChip(job['payment_status'] as String)]),
            const SizedBox(height: 6),
            RowInfo(tr('total'), money(quote['amount'] as num)),
            RowInfo(tr('paid'), money(job['paid'] as num)),
            RowInfo(tr('balance'), money(job['balance'] as num), bold: true),
            for (final p in (job['payments'] as List))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: Text('${money(p['amount'] as num)}  |  ${fmtDate(p['created_at'])}', style: const TextStyle(fontSize: 13))),
                  if (p['status'] == 'success')
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(paymentId: p['id'] as String))), child: Text(tr('receipt')))
                  else
                    StatusChip(p['status'] as String),
                ]),
              ),
            if (role == 'client' && status != 'cancelled' && (job['balance'] as num) > 0 && (job['pending'] as num) < (job['balance'] as num)) ...[
              const SizedBox(height: 12),
              PillButton(tr('pay_now'), icon: Icons.payments_outlined, onPressed: () => _pay(context)),
            ],
            if (role == 'client' && (job['balance'] as num) > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('pay_in_app'), style: TextStyle(color: cs.secondary, fontSize: 12.5))),
          ]),
        ),
      // rating
      if (job['rating'] != null)
        AppCard(child: Row(children: [for (var i = 1; i <= 5; i++) Icon(i <= (job['rating']['rating'] as int) ? Icons.star_rounded : Icons.star_border_rounded, color: brandYellow), const SizedBox(width: 10), Expanded(child: Text((job['rating']['comment'] ?? '').toString()))])),
      if (role == 'client' && status == 'completed' && job['rating'] == null) PillButton(tr('rate_fundi'), icon: Icons.star_outline_rounded, onPressed: () => _rate(context)),
    ];

    // ---- actions
    final actions = <Widget>[];
    void add(Widget w) => actions..add(w)..add(const SizedBox(height: 10));
    if (role == 'fundi') {
      if (status == 'pending' && fundi == null) add(PillButton(tr('accept_job'), icon: Icons.check_circle_outline, onPressed: () => _act(context, () => Api.post('/fundi/jobs/$id/accept'), okMsg: tr('job_accepted_ok'))));
      if (isMyFundiJob) {
        if (status == 'accepted') add(PillButton(tr('on_my_way'), icon: Icons.directions_walk, onPressed: () => _act(context, () => Api.post('/fundi/jobs/$id/on-the-way'))));
        if (status == 'accepted' || status == 'on_the_way') {
          add(PillButton(tr('i_arrived'), icon: Icons.my_location, onPressed: () => _act(context, () async {
                final p = await getPosition();
                await Api.post('/fundi/jobs/$id/arrived', {'lat': p.latitude, 'lng': p.longitude});
              }, okMsg: tr('arrival_confirmed'))));
        }
        if (['accepted', 'on_the_way', 'arrived', 'in_progress'].contains(status)) add(PillButton(tr(quote == null ? 'add_quotation' : 'edit_quotation'), icon: Icons.request_quote_outlined, outlined: true, onPressed: () => _quote(context)));
        if (status == 'arrived') add(PillButton(tr('start_work'), icon: Icons.play_arrow_rounded, onPressed: () => _act(context, () => Api.post('/fundi/jobs/$id/start'))));
        if (status == 'in_progress') add(PillButton(tr('complete_job'), icon: Icons.task_alt, onPressed: () => _act(context, () => Api.post('/fundi/jobs/$id/complete'), okMsg: tr('job_completed_ok'))));
      }
    }
    if (role == 'client' && open) {
      add(PillButton(tr('cancel_request'), outlined: true, danger: true, onPressed: () async {
        final ok = await confirmDialog(context, tr('cancel_request'), tr(['arrived', 'in_progress'].contains(status) ? 'cancel_confirm_nauli' : 'cancel_confirm'), danger: true);
        if (!ok || !context.mounted) return;
        final reason = await inputSheet(context, title: tr('reason_optional'), label: tr('reason'));
        if (reason == null || !context.mounted) return;
        _act(context, () => Api.post('/jobs/$id/cancel', {'reason': reason}));
      }));
    }
    if (role == 'admin' && open) {
      add(PillButton(tr('reassign'), icon: Icons.swap_horiz, outlined: true, onPressed: () async {
        final list = await busyVal<List<J>>(context, () async => asList(await Api.get('/admin/available-fundis?job_id=$id')));
        if (list == null || !context.mounted) return;
        if (list.isEmpty) return toast(context, tr('no_fundis_for_job'));
        final pick = await pickSheet<String>(context, tr('choose_fundi'), [for (final f in list) (f['id'] as String, '${who(f)}  (${f['phone'] ?? ''})')]);
        if (pick == null || !context.mounted) return;
        _act(context, () => Api.post('/admin/jobs/$id/reassign', {'fundi_id': pick}), okMsg: tr('saved'));
      }));
      add(PillButton(tr('cancel_job'), outlined: true, danger: true, onPressed: () async {
        final reason = await inputSheet(context, title: tr('cancel_job'), label: tr('reason'), action: tr('cancel_job'));
        if (reason == null || !context.mounted) return;
        _act(context, () => Api.post('/admin/jobs/$id/cancel', {'reason': reason}));
      }));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [...children, ...actions]);
  }

  Future<void> _pay(BuildContext c) async {
    final s = c.read<AppState>();
    final methods = <String>[for (final e in ((s.config['payment_methods'] ?? {}) as Map).entries) if (e.value == true) e.key.toString()];
    if (methods.isEmpty) return toast(c, tr('err_method_disabled'));
    final res = await showModalBottomSheet<J>(
      context: c, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _PaySheet(balance: (job['balance'] as num) - (job['pending'] as num), methods: methods),
    );
    if (res == null || !c.mounted) return;
    J? out;
    final ok = await busy(c, () async => out = asMap(await Api.post('/jobs/${job['id']}/pay', res)));
    if (!ok) return;
    await reload();
    if (!c.mounted) return;
    final pay = asMap(out!['payment']);
    toast(c, tr(pay['status'] == 'success' ? 'pay_success' : 'pay_pending'));
    if (pay['status'] == 'success') Navigator.push(c, MaterialPageRoute(builder: (_) => ReceiptPage(paymentId: pay['id'] as String)));
  }

  Future<void> _rate(BuildContext c) async {
    final res = await showModalBottomSheet<J>(context: c, isScrollControlled: true, showDragHandle: true, builder: (_) => const _RateSheet());
    if (res == null || !c.mounted) return;
    _act(c, () => Api.post('/jobs/${job['id']}/rate', res), okMsg: tr('thanks_rating'));
  }

  Future<void> _quote(BuildContext c) async {
    final res = await showModalBottomSheet<J>(
      context: c, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _QuoteSheet(initial: job['quotation'] == null ? null : asMap(job['quotation'])),
    );
    if (res == null || !c.mounted) return;
    _act(c, () => Api.put('/fundi/jobs/${job['id']}/quotation', res), okMsg: tr('saved'));
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String? time;
  final bool reached, last, danger;
  const _TimelineRow({required this.label, this.time, required this.reached, required this.last, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = danger ? cs.error : (reached ? const Color(0xFF2F855A) : cs.outline);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 28, child: Column(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: reached ? col : Colors.transparent, border: Border.all(color: col, width: 2))),
          if (!last) Expanded(child: Container(width: 2, color: col.withOpacity(.5))),
        ])),
        Expanded(child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: reached ? FontWeight.w700 : FontWeight.w500, color: reached ? null : cs.secondary)),
            if (time != null) Text(fmtDate(time), style: TextStyle(fontSize: 12, color: cs.secondary)),
          ]),
        )),
      ]),
    );
  }
}

// ===================================================================== sheets
class _PaySheet extends StatefulWidget {
  final num balance;
  final List<String> methods;
  const _PaySheet({required this.balance, required this.methods});
  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final _amount = TextEditingController(text: widget.balance.round().toString());
  final _phone = TextEditingController();
  late String method = widget.methods.first;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('pay_now'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${tr('balance')}: ${money(widget.balance)}', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          const SizedBox(height: 16),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('amount'), prefixText: 'TSh ')),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in widget.methods)
              ChoiceChip(label: Text(tr('pm_$m')), selected: method == m, shape: const StadiumBorder(), onSelected: (_) => setState(() => method = m)),
          ]),
          if (method == 'mobile_money') ...[
            const SizedBox(height: 14),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('mobile_number'))),
          ],
          const SizedBox(height: 18),
          PillButton(tr('pay_now'), onPressed: () {
            final a = num.tryParse(_amount.text.trim());
            if (a == null || a <= 0) return toast(context, tr('err_invalid_amount'));
            Navigator.pop(context, {'amount': a, 'method': method, 'phone': _phone.text.trim()});
          }),
        ]),
      ),
    );
  }
}

class _RateSheet extends StatefulWidget {
  const _RateSheet();
  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int stars = 5;
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('rate_fundi'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(iconSize: 40, onPressed: () => setState(() => stars = i), icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_border_rounded, color: brandYellow)),
        ]),
        TextField(controller: _c, maxLines: 3, decoration: InputDecoration(hintText: tr('comment_optional'))),
        const SizedBox(height: 16),
        PillButton(tr('send'), onPressed: () => Navigator.pop(context, {'rating': stars, 'comment': _c.text.trim()})),
      ]),
    );
  }
}

class _QuoteSheet extends StatefulWidget {
  final J? initial;
  const _QuoteSheet({this.initial});
  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  late final _amount = TextEditingController(text: widget.initial == null ? '' : (widget.initial!['amount'] as num).round().toString());
  late final _note = TextEditingController(text: (widget.initial?['note'] ?? '').toString());
  late bool transport = widget.initial?['includes_transport'] == true;
  late final List<String> files = [for (final f in (widget.initial?['file_ids'] ?? []) as List) f as String];

  Future<void> _attach() async {
    final p = await pickDocument(context);
    if (p == null || !mounted) return;
    String? id;
    final ok = await busy(context, () async => id = (await Api.upload(p))['id'] as String);
    if (ok && id != null) setState(() => files.add(id!));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('quotation'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('amount_to_pay'), prefixText: 'TSh ')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('includes_transport')), value: transport, onChanged: (v) => setState(() => transport = v)),
          TextField(controller: _note, maxLines: 3, decoration: InputDecoration(hintText: tr('note'))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < files.length; i++) Chip(label: Text('${tr('attachment')} ${i + 1}'), shape: const StadiumBorder(), onDeleted: () => setState(() => files.removeAt(i))),
            ActionChip(avatar: const Icon(Icons.attach_file, size: 18), label: Text(tr('attach_quotation')), shape: const StadiumBorder(), onPressed: _attach),
          ]),
          const SizedBox(height: 16),
          PillButton(tr('save'), onPressed: () {
            final a = num.tryParse(_amount.text.trim());
            if (a == null || a <= 0) return toast(context, tr('err_invalid_amount'));
            Navigator.pop(context, {'amount': a, 'includes_transport': transport, 'note': _note.text.trim(), 'file_ids': files});
          }),
        ]),
      ),
    );
  }
}

// ===================================================================== receipt
class ReceiptPage extends StatelessWidget {
  final String paymentId;
  const ReceiptPage({super.key, required this.paymentId});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('receipt'))),
      body: Loader<J>(
        load: () async => asMap(await Api.get('/payments/$paymentId/receipt')),
        builder: (c, r, _) {
          final rows = <(String, String)>[
            (tr('receipt_no'), '${r['receipt_no']}'),
            (tr('date_time'), fmtDate(r['paid_at'])),
            (tr('client'), '${r['client_name']}'),
            (tr('fundi'), '${r['fundi_name'] ?? ''}'),
            (tr('fundi_phone'), '${r['fundi_phone'] ?? ''}'),
            (tr('service'), '${r['service_name']}'),
            (tr('job_code'), '${r['job_code']}'),
            (tr('location'), '${r['location']}'),
            (tr('payment_method'), tr('pm_${r['method']}')),
            (tr('amount_paid'), money(r['amount_paid'] as num)),
            if (r['quoted'] != null) (tr('total'), money(r['quoted'] as num)),
            (tr('total_paid'), money(r['total_paid'] as num)),
            if (r['balance'] != null) (tr('balance'), money(r['balance'] as num)),
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            AppCard(
              child: Column(children: [
                const LogoMark(56),
                const SizedBox(height: 8),
                const Wordmark(size: 22),
                const SizedBox(height: 4),
                Text(tr('payment_receipt'), style: TextStyle(color: Theme.of(c).colorScheme.secondary)),
                const Divider(height: 28),
                for (final e in rows) RowInfo(e.$1, e.$2, bold: e.$1 == tr('amount_paid')),
                const Divider(height: 28),
                Text(tr('thanks_using'), textAlign: TextAlign.center),
              ]),
            ),
            PillButton(tr('copy_receipt'), icon: Icons.copy, outlined: true, onPressed: () {
              Clipboard.setData(ClipboardData(text: 'SmartFundi\n${rows.map((e) => '${e.$1}: ${e.$2}').join('\n')}'));
              toast(c, tr('copied'));
            }),
          ]);
        },
      ),
    );
  }
}

// ===================================================================== chat
class ChatPage extends StatefulWidget {
  final String jobId, title;
  const ChatPage({super.key, required this.jobId, required this.title});
  @override
  State<ChatPage> createState() => _ChatState();
}

class _ChatState extends State<ChatPage> {
  final List<J> msgs = [];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _t;
  int last = 0;
  String? phone;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _job();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _job() async {
    try {
      final j = asMap(await Api.get('/jobs/${widget.jobId}'));
      final role = context.read<AppState>().role;
      final other = role == 'client' ? j['fundi'] : j['client'];
      if (mounted) setState(() => phone = other == null ? null : (other['phone'] ?? '').toString());
    } catch (_) {}
  }

  Future<void> _poll() async {
    try {
      final r = asList(await Api.get('/jobs/${widget.jobId}/messages?after=$last'));
      if (!mounted) return;
      setState(() => loaded = true);
      if (r.isNotEmpty) {
        setState(() {
          msgs.addAll(r);
          last = r.last['id'] as int;
        });
        _down();
      }
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    try {
      await Api.post('/jobs/${widget.jobId}/messages', {'body': t});
      await _poll();
    } catch (e) {
      if (mounted) {
        toast(context, errText(e));
        _ctrl.text = t;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final me = s.user!['id'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (phone != null) ...[
          IconButton(onPressed: () => openUri(context, telUri(phone!)), icon: const Icon(Icons.call_outlined)),
          IconButton(onPressed: () => openUri(context, waUri(phone!)), icon: const Icon(Icons.forum_outlined)),
        ],
      ]),
      body: Column(children: [
        if (s.role == 'client') const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 0), child: NauliNotice(compact: true)),
        Expanded(
          child: !loaded
              ? const LoadingView()
              : msgs.isEmpty
                  ? EmptyView(tr('no_messages_yet'), icon: Icons.chat_bubble_outline)
                  : ListView.builder(
                      controller: _scroll, padding: const EdgeInsets.all(12), itemCount: msgs.length,
                      itemBuilder: (_, i) {
                        final m = msgs[i];
                        final mine = m['sender_id'] == me;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                            decoration: BoxDecoration(color: mine ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((m['body'] ?? '').toString(), style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface)),
                              const SizedBox(height: 2),
                              Text(fmtDate(m['created_at']), style: TextStyle(fontSize: 10.5, color: (mine ? cs.onPrimary : cs.onSurface).withOpacity(.65))),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: _ctrl, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: tr('type_message')))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ===================================================================== notifications / messages
class NotificationsPage extends StatefulWidget {
  final bool embedded;
  const NotificationsPage({super.key, this.embedded = false});
  @override
  State<NotificationsPage> createState() => _NotifState();
}

class _NotifState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    if (!widget.embedded) Future.delayed(const Duration(seconds: 2), () => mounted ? context.read<AppState>().markAllRead() : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('notifications')), automaticallyImplyLeading: !widget.embedded),
      body: Loader<List<J>>(
        load: () async => asList((await Api.get('/notifications') as Map)['items']),
        every: const Duration(seconds: 20),
        builder: (c, items, reload) => items.isEmpty
            ? EmptyView(tr('no_notifications'), icon: Icons.notifications_none)
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: items.length,
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final unread = n['read'] != true;
                    return AppCard(
                      onTap: n['job_id'] == null ? null : () => Navigator.push(c, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: n['job_id'] as String))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 6, right: 12), child: CircleAvatar(radius: 5, backgroundColor: unread ? Theme.of(c).colorScheme.primary : Colors.transparent)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((n['title'] ?? '').toString(), style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text((n['body'] ?? '').toString(), style: const TextStyle(height: 1.35)),
                          const SizedBox(height: 4),
                          Text(fmtDate(n['created_at']), style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.secondary)),
                        ])),
                      ]),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class BellButton extends StatelessWidget {
  const BellButton({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return IconButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
      icon: Badge(isLabelVisible: s.unread > 0, label: Text('${s.unread}'), child: const Icon(Icons.notifications_outlined)),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('messages'))),
      body: Loader<List<J>>(
        load: () async => asList(await Api.get('/jobs/chats')),
        every: const Duration(seconds: 15),
        builder: (c, items, reload) => items.isEmpty
            ? EmptyView(tr('no_chats'), icon: Icons.chat_bubble_outline)
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    return AppCard(
                      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatPage(jobId: m['id'] as String, title: (m['other_name'] ?? '').toString()))),
                      child: Row(children: [
                        Avatar(name: (m['other_name'] ?? '').toString()),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text((m['other_name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(m['last_message'] == null ? tr('no_messages_yet') : m['last_message'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(c).colorScheme.secondary)),
                        ])),
                        Text(m['code'].toString(), style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.secondary)),
                      ]),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

// ===================================================================== settings / about
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _support(BuildContext c, AppState s) => showModalBottomSheet(
        context: c, showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('support'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(tr('support_sub'), style: TextStyle(color: Theme.of(c).colorScheme.secondary)),
              const SizedBox(height: 16),
              for (final p in s.supportPhones) ...[Text(p, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), ContactRow(p), const SizedBox(height: 16)],
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final u = s.user!;
    Widget tile(IconData i, String t, VoidCallback f, {String? sub, Widget? trailing}) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(i), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: sub == null ? null : Text(sub), trailing: trailing ?? const Icon(Icons.chevron_right), onTap: f),
        );
    final langName = {'sw': 'Kiswahili', 'en': 'English', 'fr': 'Français'}[s.lang]!;
    return Scaffold(
      appBar: AppBar(title: Text(tr('settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Row(children: [
            Avatar(fileId: u['photo_file_id'] as String?, name: s.name, size: 56),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name.isEmpty ? '-' : s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text((u['phone'] ?? u['email'] ?? '').toString(), style: TextStyle(color: cs.secondary)),
            ])),
          ]),
        ),
        tile(Icons.badge_outlined, tr('full_name'), () async {
          final v = await inputSheet(context, title: tr('full_name'), initial: s.name);
          if (v == null || v.isEmpty || !context.mounted) return;
          final ok = await busy(context, () async => s.setUser(asMap((await Api.put('/auth/me', {'name': v}) as Map)['user'])));
          if (ok) toast(context, tr('saved'));
        }, sub: s.name),
        if (s.role == 'client')
          tile(Icons.location_on_outlined, tr('your_area'), () async {
            final v = await pickLocation(context);
            if (v == null || !context.mounted) return;
            final ok = await busy(context, () async {
              final r = await Api.put('/auth/me', {'region_id': v['region_id'], 'district_id': v['district_id'], 'ward_id': v['ward_id']}) as Map;
              s.saveLocLabel(v['label'] as String);
              s.setUser(asMap(r['user']));
            });
            if (ok) toast(context, v['active'] == true ? tr('saved') : tr('err_area_not_available'));
          }, sub: s.locLabel.isEmpty ? tr('tap_to_set') : s.locLabel),
        tile(Icons.language, tr('language'), () async {
          final l = await pickSheet<String>(context, tr('language'), const [('sw', 'Kiswahili'), ('en', 'English'), ('fr', 'Français')]);
          if (l != null) s.setLang(l);
        }, sub: langName),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.dark_mode_outlined), title: Text(tr('night_mode'), style: const TextStyle(fontWeight: FontWeight.w700)), value: s.themeMode == ThemeMode.dark, onChanged: s.setDark),
        ),
        tile(Icons.info_outline, tr('about_us'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()))),
        tile(Icons.privacy_tip_outlined, tr('privacy_terms'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()))),
        tile(Icons.support_agent, tr('support'), () => _support(context, s)),
        const SizedBox(height: 8),
        PillButton(tr('logout'), outlined: true, danger: true, icon: Icons.logout, onPressed: () async {
          if (await confirmDialog(context, tr('logout'), tr('logout_confirm'), danger: true) && context.mounted) s.logout();
        }),
        const SizedBox(height: 16),
        Center(child: Text('SmartFundi v1.0.0', style: TextStyle(color: cs.secondary, fontSize: 12))),
      ]),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.about;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('about_us'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Column(children: [const LogoMark(88), const SizedBox(height: 10), const Wordmark(size: 30), const SizedBox(height: 4), Text('v1.0.0', style: TextStyle(color: cs.secondary))])),
        const SizedBox(height: 20),
        AppCard(child: Text(tr('about_desc'), style: const TextStyle(height: 1.5))),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('in_collab'), style: TextStyle(color: cs.secondary)),
            Text((a['partner'] ?? 'G TECH ELECTRICAL SERVICES').toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Divider(height: 24),
            RowInfo(tr('location'), (a['location'] ?? 'Mbeya').toString()),
            RowInfo('P.O. Box', (a['po_box'] ?? '131, Mbeya').toString()),
            for (final p in s.supportPhones) RowInfo(tr('phone'), p),
          ]),
        ),
        for (final p in s.supportPhones.take(1)) ContactRow(p),
      ]),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('privacy_terms'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(child: Text(tr('privacy_text'), style: const TextStyle(height: 1.5))),
        PillButton(tr('read_more'), icon: Icons.open_in_new, outlined: true, onPressed: () {
          final url = (s.config['landing_url'] ?? '').toString();
          if (url.isEmpty) return toast(context, tr('landing_soon'));
          openUri(context, Uri.parse(url));
        }),
      ]),
    );
  }
}
