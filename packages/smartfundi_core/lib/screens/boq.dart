import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'shared.dart';

/// Section / item numbers, worked out the same way as on the server (1, 1.1, 1.2 ...).
List<J> _number(List<J> rows) {
  var sec = 0, n = 0;
  for (final r in rows) {
    final k = r['kind'];
    if (k == 'section') {
      sec++;
      n = 0;
      r['no'] = '$sec';
    } else if (k == 'item' || k == 'group') {
      n++;
      r['no'] = sec > 0 ? '$sec.$n' : '$n';
    } else {
      r['no'] = '';
    }
  }
  return rows;
}

bool _priced(Object? k) => k == 'item' || k == 'sub';
num _n(Object? v) => v is num ? v : (num.tryParse('$v'.replaceAll(',', '')) ?? 0);
num _amount(J l) => _priced(l['kind']) ? (_n(l['qty']) * _n(l['rate'])) : 0;

// ===================================================================== BOQ list
/// Fundi / Company: own BOQs (create new, open, delete). Admin: every BOQ with download buttons.
class BoqListPage extends StatefulWidget {
  final bool admin;
  final bool embedded; // inside a tab (no back button)
  const BoqListPage({super.key, this.admin = false, this.embedded = false});
  @override
  State<BoqListPage> createState() => _BoqListState();
}

class _BoqListState extends State<BoqListPage> {
  int _k = 0;
  Future<void> _new() async {
    J? b;
    final ok = await busy(context, () async => b = asMap(await Api.post('/boq', {})));
    if (!ok || b == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BoqPage(boqId: b!['id'] as String, editable: true)));
    if (mounted) setState(() => _k++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(tr('boq')),
        actions: [
          if (widget.admin) IconButton(tooltip: tr('boq_master'), icon: const Icon(Icons.edit_note), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BoqMasterPage(admin: true)))),
        ],
      ),
      floatingActionButton: widget.admin ? null : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add), label: Text(tr('new_boq'))),
      body: Loader<List<J>>(
        key: ValueKey(_k),
        load: () async => asList(await Api.get(widget.admin ? '/boq/all' : '/boq/mine')),
        builder: (c, list, reload) {
          if (list.isEmpty) return EmptyView(tr('no_boq'), icon: Icons.table_chart_outlined);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final b = list[i];
                return AppCard(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => BoqPage(boqId: b['id'] as String, editable: !widget.admin)));
                    reload();
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text((b['title'] ?? 'BOQ').toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(money(b['total'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 4),
                    Text([if ((b['client_name'] ?? '').toString().isNotEmpty) b['client_name'], if (b['job_code'] != null) b['job_code'], if (widget.admin && b['owner_name'] != null) b['owner_name']].join('  |  '),
                        style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 13)),
                    Text(fmtDate(b['updated_at']), style: TextStyle(color: Theme.of(c).colorScheme.secondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(children: [
                      TextButton.icon(onPressed: () => openUri(context, Api.boqExportUri(b['id'] as String, 'pdf')), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF')),
                      TextButton.icon(onPressed: () => openUri(context, Api.boqExportUri(b['id'] as String, 'xlsx')), icon: const Icon(Icons.grid_on, size: 18), label: const Text('Excel')),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!await confirmDialog(context, tr('delete'), tr('delete_boq_confirm'), danger: true) || !context.mounted) return;
                          if (await busy(context, () async => await Api.delete('/boq/${b['id']}'))) reload();
                        },
                      ),
                    ]),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ===================================================================== BOQ editor / viewer
class BoqPage extends StatefulWidget {
  final String boqId;
  final bool editable;
  const BoqPage({super.key, required this.boqId, this.editable = false});
  @override
  State<BoqPage> createState() => _BoqPageState();
}

class _BoqPageState extends State<BoqPage> {
  J? _b;
  List<J> _lines = [];
  bool _dirty = false, _loading = true, _onlyQty = false;
  String _find = '';
  Object? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = asMap(await Api.get('/boq/${widget.boqId}'));
      if (!mounted) return;
      setState(() {
        _b = b;
        _lines = _number(asList(b['lines']));
        _loading = false;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() { _err = e; _loading = false; });
    }
  }

  num get _total => _lines.fold<num>(0, (a, l) => a + _amount(l));

  Future<bool> _save() async {
    final b = _b!;
    final ok = await busy(context, () async {
      final r = asMap(await Api.put('/boq/${widget.boqId}', {
        'title': b['title'], 'client_name': b['client_name'], 'client_contact': b['client_contact'], 'location': b['location'], 'tin': b['tin'],
        'installer_name': b['installer_name'], 'installer_phone': b['installer_phone'],
        'lines': [for (final l in _lines) {'item_id': l['item_id'], 'kind': l['kind'], 'desc': l['desc'], 'unit': l['unit'], 'rate': l['rate'], 'qty': l['qty']}],
      }));
      _b = r;
      _lines = _number(asList(r['lines']));
    });
    if (ok) {
      setState(() => _dirty = false);
      if (mounted) toast(context, tr('saved'));
    }
    return ok;
  }

  Future<void> _download(String fmt) async {
    if (widget.editable && _dirty && !await _save()) return;
    if (!mounted) return;
    await openUri(context, Api.boqExportUri(widget.boqId, fmt));
  }

  Future<void> _editHeader(String key, String label, {TextInputType? type}) async {
    final v = await inputSheet(context, title: label, initial: (_b![key] ?? '').toString(), type: type);
    if (v == null) return;
    setState(() {
      _b![key] = v;
      _dirty = true;
    });
  }

  Future<void> _editLine(J l) async {
    final r = await showModalBottomSheet<J>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _LineSheet(line: l, freeText: l['item_id'] == null),
    );
    if (r == null) return;
    setState(() {
      l.addAll(r);
      _dirty = true;
    });
  }

  Future<void> _addLine() async {
    final sections = [for (var i = 0; i < _lines.length; i++) if (_lines[i]['kind'] == 'section') i];
    int? at;
    if (sections.isNotEmpty) {
      final pick = await pickSheet<int>(context, tr('boq_where'), [
        for (final i in sections) (i, '${_lines[i]['no']}. ${_lines[i]['desc']}'),
        (-1, tr('boq_at_end')),
      ], search: true);
      if (pick == null || !mounted) return;
      if (pick >= 0) {
        var end = pick + 1;
        while (end < _lines.length && _lines[end]['kind'] != 'section') {
          end++;
        }
        at = end;
      }
    }
    final r = await showModalBottomSheet<J>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _LineSheet(line: {'kind': 'item', 'desc': '', 'unit': '', 'rate': 0, 'qty': 1}, freeText: true),
    );
    if (r == null || (r['desc'] ?? '').toString().trim().isEmpty) return;
    setState(() {
      final l = {'item_id': null, 'kind': 'item', ...r};
      if (at == null) {
        _lines.add(l);
      } else {
        _lines.insert(at, l);
      }
      _number(_lines);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return Scaffold(appBar: AppBar(title: Text(tr('boq'))), body: const LoadingView());
    if (_err != null || _b == null) return Scaffold(appBar: AppBar(title: Text(tr('boq'))), body: ErrorView(_err ?? 'error', _load));
    final b = _b!;
    final ed = widget.editable;
    final shown = [
      for (final l in _lines)
        if ((!_onlyQty || !_priced(l['kind']) || _n(l['qty']) > 0) && (_find.isEmpty || '${l['desc']}'.toLowerCase().contains(_find.toLowerCase()))) l,
    ];
    Widget info(String key, String label, {TextInputType? type}) => ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          title: Text(label, style: TextStyle(color: cs.secondary, fontSize: 12)),
          subtitle: Text((b[key] ?? '').toString().isEmpty ? '-' : b[key].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: ed ? const Icon(Icons.edit_outlined, size: 18) : null,
          onTap: ed ? () => _editHeader(key, label, type: type) : null,
        );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final save = await confirmDialog(context, tr('unsaved'), tr('unsaved_sub'), yes: tr('save'));
        if (save) {
          if (await _save() && mounted) Navigator.pop(context);
        } else if (mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text((b['title'] ?? 'BOQ').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _download('pdf')),
            IconButton(tooltip: 'Excel', icon: const Icon(Icons.grid_on), onPressed: () => _download('xlsx')),
            if (ed) IconButton(tooltip: tr('save'), icon: Icon(Icons.save_outlined, color: _dirty ? brandOrange : null), onPressed: _dirty ? _save : null),
          ],
        ),
        floatingActionButton: ed ? FloatingActionButton(onPressed: _addLine, tooltip: tr('add_boq_item'), child: const Icon(Icons.add)) : null,
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(gradient: brandGradient),
            child: Row(children: [
              Text(tr('grand_total'), style: const TextStyle(color: Colors.white70)),
              const Spacer(),
              Text(money(_total), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          itemCount: shown.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppCard(
                  child: Column(children: [
                    info('title', tr('boq_title')),
                    info('client_name', tr('client')),
                    info('client_contact', tr('client_phone'), type: TextInputType.phone),
                    info('location', tr('location')),
                    info('tin', 'TIN'),
                    info('installer_name', tr('installer')),
                    info('installer_phone', tr('phone'), type: TextInputType.phone),
                  ]),
                ),
                if (ed) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('boq_private_hint'), style: TextStyle(color: cs.secondary, fontSize: 12.5, height: 1.4))),
                Row(children: [
                  Expanded(child: TextField(decoration: InputDecoration(hintText: tr('search'), prefixIcon: const Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _find = v.trim()))),
                  const SizedBox(width: 8),
                  FilterChip(label: Text(tr('boq_only_qty')), selected: _onlyQty, onSelected: (v) => setState(() => _onlyQty = v)),
                ]),
                const SizedBox(height: 8),
              ]);
            }
            final l = shown[i - 1];
            final k = l['kind'] as String;
            if (k == 'section') {
              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(12)),
                child: Text('${l['no']}.  ${l['desc']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              );
            }
            if (!_priced(k)) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                child: Text('${(l['no'] ?? '').toString().isEmpty ? '' : '${l['no']}  '}${l['desc']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            }
            final amt = _amount(l);
            return InkWell(
              onTap: ed ? () => _editLine(l) : null,
              onLongPress: ed && l['item_id'] == null ? () => setState(() { _lines.remove(l); _number(_lines); _dirty = true; }) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.5)))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 38, child: Text((l['no'] ?? '').toString(), style: TextStyle(color: cs.secondary, fontSize: 12))),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((l['desc'] ?? '').toString()),
                    const SizedBox(height: 2),
                    Text('${_n(l['qty'])} ${l['unit'] ?? ''}  x  ${money(_n(l['rate']))}', style: TextStyle(color: cs.secondary, fontSize: 12.5)),
                  ])),
                  Text(amt > 0 ? money(amt) : '-', style: TextStyle(fontWeight: amt > 0 ? FontWeight.w800 : FontWeight.w400)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LineSheet extends StatefulWidget {
  final J line;
  final bool freeText;
  const _LineSheet({required this.line, required this.freeText});
  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final _desc = TextEditingController(text: '${widget.line['desc'] ?? ''}');
  late final _unit = TextEditingController(text: '${widget.line['unit'] ?? ''}');
  late final _rate = TextEditingController(text: _fmt(widget.line['rate']));
  late final _qty = TextEditingController(text: _fmt(widget.line['qty']));
  String _fmt(Object? v) => v == null ? '' : (_n(v) == _n(v).roundToDouble() ? _n(v).round().toString() : _n(v).toString());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.freeText)
            TextField(controller: _desc, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('description')))
          else
            Text('${widget.line['desc']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: _qty, autofocus: !widget.freeText, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('quantity')))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _unit, decoration: InputDecoration(labelText: tr('unit')))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('unit_price'), prefixText: 'TSh ')),
          const SizedBox(height: 18),
          PillButton(tr('save'), onPressed: () => Navigator.pop(context, <String, dynamic>{
                'desc': _desc.text.trim().isEmpty ? widget.line['desc'] : _desc.text.trim(),
                'unit': _unit.text.trim(),
                'rate': _n(_rate.text),
                'qty': _n(_qty.text),
              })),
        ]),
      ),
    );
  }
}

// ===================================================================== master list (Admin)
/// The Admin edits the master list once; the change shows for every Fundi and Company.
class BoqMasterPage extends StatefulWidget {
  final bool admin;
  const BoqMasterPage({super.key, this.admin = true});
  @override
  State<BoqMasterPage> createState() => _BoqMasterState();
}

class _BoqMasterState extends State<BoqMasterPage> {
  int _k = 0;
  String _find = '';
  void _refresh() => setState(() => _k++);

  Future<void> _edit(J it) async {
    final isItem = _priced(it['kind']);
    final r = await showModalBottomSheet<J>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _MasterSheet(item: it, priced: isItem),
    );
    if (r == null || !mounted) return;
    if (r['delete'] == true) {
      if (!await confirmDialog(context, tr('delete'), tr('delete_boq_item_confirm'), danger: true) || !mounted) return;
      if (await busy(context, () async => await Api.delete('/boq/master/items/${it['id']}'))) _refresh();
      return;
    }
    if (await busy(context, () async => await Api.put('/boq/master/items/${it['id']}', r))) _refresh();
  }

  Future<void> _add(List<J> items) async {
    final kind = await pickSheet<String>(context, tr('add_boq_item'), [('item', tr('boq_kind_item')), ('section', tr('boq_kind_section')), ('group', tr('boq_kind_group')), ('sub', tr('boq_kind_sub'))]);
    if (kind == null || !mounted) return;
    int? after;
    if (kind != 'section') {
      final secs = [for (final i in items) if (i['kind'] == 'section') i];
      final pick = await pickSheet<int>(context, tr('boq_where'), [for (final s in secs) (s['id'] as int, '${s['no']}. ${s['description']}'), (0, tr('boq_at_end'))], search: true);
      if (pick == null || !mounted) return;
      if (pick != 0) {
        // place at the end of the chosen section
        final idx = items.indexWhere((i) => i['id'] == pick);
        var end = idx;
        while (end + 1 < items.length && items[end + 1]['kind'] != 'section') {
          end++;
        }
        after = items[end]['id'] as int;
      }
    }
    final r = await showModalBottomSheet<J>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _MasterSheet(item: {'kind': kind, 'description': '', 'unit': '', 'rate': 0}, priced: _priced(kind), isNew: true),
    );
    if (r == null || !mounted || (r['description'] ?? '').toString().trim().isEmpty) return;
    if (await busy(context, () async => await Api.post('/boq/master/items', {...r, 'kind': kind, if (after != null) 'after_id': after}))) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canEdit = context.watch<AppState>().user?['is_main_admin'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('boq_master'))),
      body: Loader<J>(
        key: ValueKey(_k),
        load: () async => asMap(await Api.get('/boq/master')),
        builder: (c, d, reload) {
          final items = asList(d['items']);
          final shown = [for (final i in items) if (_find.isEmpty || '${i['description']}'.toLowerCase().contains(_find.toLowerCase())) i];
          return Scaffold(
            floatingActionButton: canEdit ? FloatingActionButton(onPressed: () => _add(items), child: const Icon(Icons.add)) : null,
            body: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              itemCount: shown.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Column(children: [
                    AppCard(
                      onTap: canEdit
                          ? () async {
                              final v = await inputSheet(context, title: tr('boq_title'), initial: '${d['title']}');
                              if (v == null || v.isEmpty || !context.mounted) return;
                              if (await busy(context, () async => await Api.put('/boq/master/title', {'title': v}))) _refresh();
                            }
                          : null,
                      child: Row(children: [
                        Expanded(child: Text('${d['title']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        if (canEdit) const Icon(Icons.edit_outlined, size: 18),
                      ]),
                    ),
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('boq_master_hint'), style: TextStyle(color: cs.secondary, fontSize: 12.5, height: 1.4))),
                    TextField(decoration: InputDecoration(hintText: tr('search'), prefixIcon: const Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _find = v.trim())),
                    const SizedBox(height: 8),
                  ]);
                }
                final it = shown[i - 1];
                final k = it['kind'] as String;
                final head = k == 'section';
                return InkWell(
                  onTap: canEdit ? () => _edit(it) : null,
                  child: Container(
                    margin: EdgeInsets.only(top: head ? 10 : 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: head ? brandBlue : null, borderRadius: head ? BorderRadius.circular(12) : null,
                      border: head ? null : Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.5))),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 38, child: Text('${it['no'] ?? ''}', style: TextStyle(fontSize: 12, color: head ? Colors.white70 : cs.secondary))),
                      Expanded(child: Text('${it['description']}', style: TextStyle(fontWeight: head || k == 'group' ? FontWeight.w800 : FontWeight.w400, color: head ? Colors.white : null))),
                      if (_priced(k)) Padding(padding: const EdgeInsets.only(left: 8), child: Text('${money(_n(it['master_rate']))} / ${it['unit'] ?? ''}', style: const TextStyle(fontSize: 12.5))),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _MasterSheet extends StatefulWidget {
  final J item;
  final bool priced, isNew;
  const _MasterSheet({required this.item, required this.priced, this.isNew = false});
  @override
  State<_MasterSheet> createState() => _MasterSheetState();
}

class _MasterSheetState extends State<_MasterSheet> {
  late final _desc = TextEditingController(text: '${widget.item['description'] ?? ''}');
  late final _unit = TextEditingController(text: '${widget.item['unit'] ?? ''}');
  late final _rate = TextEditingController(text: '${_n(widget.item['master_rate'] ?? widget.item['rate']).round()}');
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _desc, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: tr('description'))),
          if (widget.priced) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _unit, decoration: InputDecoration(labelText: tr('unit')))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('unit_price')))),
            ]),
          ],
          const SizedBox(height: 18),
          PillButton(tr('save'), onPressed: () => Navigator.pop(context, <String, dynamic>{
                'description': _desc.text.trim(),
                if (widget.priced) ...{'unit': _unit.text.trim(), 'rate': _n(_rate.text)},
              })),
          if (!widget.isNew) TextButton(onPressed: () => Navigator.pop(context, <String, dynamic>{'delete': true}), child: Text(tr('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }
}
