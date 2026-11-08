import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'i18n.dart';
import 'theme.dart';

// ---------------------------------------------------------------- text helpers
String errText(Object e) {
  if (e is ApiError) {
    if (e.status == 0) return tr('err_network');
    final k = 'err_${e.code}';
    var m = hasTr(k) ? tr(k) : tr('err_generic');
    if (e.code == 'too_far' && e.data['distance_m'] != null) m = '$m (${e.data['distance_m']} m)';
    return m;
  }
  return tr('err_generic');
}

String money(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'TSh ${b.toString()}';
}

String fmtDate(dynamic iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '';
  String t(int x) => x.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)}/${d.year} ${t(d.hour)}:${t(d.minute)}';
}

String svcName(Map s) => (s['name_$currentLang'] ?? s['name_en'] ?? '').toString();
String who(Map? u) => u == null ? '' : ((u['company_name'] ?? u['name'] ?? u['phone'] ?? '') as Object).toString();

void toast(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));
}

// ---------------------------------------------------------------- busy wrapper
Future<T?> busyVal<T>(BuildContext c, Future<T> Function() f) async {
  showDialog(
    context: c,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    final r = await f();
    if (c.mounted) Navigator.of(c, rootNavigator: true).pop();
    return r;
  } catch (e) {
    if (c.mounted) {
      Navigator.of(c, rootNavigator: true).pop();
      toast(c, errText(e));
    }
    return null;
  }
}

Future<bool> busy(BuildContext c, Future<void> Function() f) async {
  final r = await busyVal<bool>(c, () async {
    await f();
    return true;
  });
  return r == true;
}

// ---------------------------------------------------------------- basic widgets
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool danger;
  final IconData? icon;
  const PillButton(this.label, {super.key, this.onPressed, this.outlined = false, this.danger = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
      Flexible(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]);
    const size = Size.fromHeight(52);
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            minimumSize: size, shape: const StadiumBorder(), foregroundColor: danger ? cs.error : null,
            side: BorderSide(color: danger ? cs.error : cs.outline)),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
          minimumSize: size, shape: const StadiumBorder(),
          backgroundColor: danger ? cs.error : null, foregroundColor: danger ? Colors.white : null),
      child: child,
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color ?? cs.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: cs.outline.withOpacity(.6))),
            child: child,
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  static Color colorOf(String s) {
    switch (s) {
      case 'pending':
      case 'partial':
      case 'unpaid':
        return const Color(0xFFB7791F);
      case 'accepted':
      case 'on_the_way':
        return const Color(0xFF2B6CB0);
      case 'arrived':
        return const Color(0xFF0F766E);
      case 'in_progress':
        return const Color(0xFF5B5BD6);
      case 'completed':
      case 'paid':
      case 'approved':
      case 'success':
        return const Color(0xFF2F855A);
      default:
        return const Color(0xFFC53030);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(.14), borderRadius: BorderRadius.circular(20)),
      child: Text(tr('st_$status'), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, this.onRetry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(errText(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(width: 200, child: PillButton(tr('retry'), onPressed: onRetry, outlined: true)),
          ]),
        ),
      );
}

/// Loads data with a visible loading state, an error state with retry, and optional auto refresh.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  final Duration? every;
  const Loader({super.key, required this.load, required this.builder, this.every});
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? data;
  Object? err;
  bool loading = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.every != null) _t = Timer.periodic(widget.every!, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        data = d;
        err = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (data == null) err = e;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      if (loading) return const LoadingView();
      return ErrorView(err ?? 'x', () => _load());
    }
    return widget.builder(context, data as T, () => _load(silent: true));
  }
}

class Wordmark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? accent;
  const Wordmark({super.key, this.size = 28, this.color, this.accent});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return RichText(
      text: TextSpan(style: TextStyle(fontSize: size, letterSpacing: -size / 28, color: c, height: 1), children: [
        const TextSpan(text: 'Smart', style: TextStyle(fontWeight: FontWeight.w500)),
        TextSpan(text: 'Fundi', style: TextStyle(fontWeight: FontWeight.w800, color: accent ?? c)),
      ]),
    );
  }
}

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark(this.size, {super.key});
  @override
  Widget build(BuildContext context) => Image.asset('assets/icon.png', width: size, height: size);
}

class FileImg extends StatelessWidget {
  final String id;
  final double? w, h;
  final double radius;
  const FileImg(this.id, {super.key, this.w, this.h, this.radius = 14});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          Api.fileUrl(id), headers: Api.authHeaders, width: w, height: h, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
              width: w, height: h, color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_not_supported_outlined)),
          loadingBuilder: (c, child, p) => p == null
              ? child
              : Container(width: w, height: h, color: Theme.of(context).colorScheme.surfaceContainerHighest),
        ),
      );
}

void showPhoto(BuildContext c, String id) => showDialog(
      context: c,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: InteractiveViewer(child: Image.network(Api.fileUrl(id), headers: Api.authHeaders, fit: BoxFit.contain)),
        ),
      ),
    );

class Avatar extends StatelessWidget {
  final String? fileId;
  final String name;
  final double size;
  const Avatar({super.key, this.fileId, required this.name, this.size = 48});
  @override
  Widget build(BuildContext context) {
    if (fileId != null) return FileImg(fileId!, w: size, h: size, radius: size / 2);
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2, backgroundColor: cs.primary.withOpacity(.14),
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size / 2.4)),
    );
  }
}

class RowInfo extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const RowInfo(this.label, this.value, {super.key, this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.secondary))),
          Expanded(flex: 6, child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}

/// Highlighted card for the mandatory nauli (transport) message.
class NauliNotice extends StatelessWidget {
  final bool compact;
  const NauliNotice({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brandYellow.withOpacity(.16), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brandYellow.withOpacity(.7)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(tr('nauli_message'), style: TextStyle(fontSize: compact ? 12.5 : 14, height: 1.4, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- sheets and dialogs
Future<T?> pickSheet<T>(BuildContext c, String title, List<(T, String)> items, {bool search = false}) {
  return showModalBottomSheet<T>(
    context: c, isScrollControlled: true, showDragHandle: true,
    builder: (_) => _PickSheet<T>(title, items, search || items.length > 12),
  );
}

class _PickSheet<T> extends StatefulWidget {
  final String title;
  final List<(T, String)> items;
  final bool search;
  const _PickSheet(this.title, this.items, this.search);
  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((e) => e.$2.toLowerCase().contains(q.toLowerCase())).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
          if (widget.search)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: TextField(decoration: InputDecoration(hintText: tr('search'), prefixIcon: const Icon(Icons.search)), onChanged: (v) => setState(() => q = v)),
            ),
          Flexible(
            child: list.isEmpty
                ? Padding(padding: const EdgeInsets.all(32), child: Text(tr('nothing_here')))
                : ListView.builder(
                    shrinkWrap: true, itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(title: Text(list[i].$2), onTap: () => Navigator.pop(context, list[i].$1)),
                  ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

Future<Set<int>?> multiPickSheet(BuildContext c, String title, List<(int, String)> items, Set<int> initial) {
  return showModalBottomSheet<Set<int>>(
    context: c, isScrollControlled: true, showDragHandle: true,
    builder: (_) => _MultiSheet(title, items, initial),
  );
}

class _MultiSheet extends StatefulWidget {
  final String title;
  final List<(int, String)> items;
  final Set<int> initial;
  const _MultiSheet(this.title, this.items, this.initial);
  @override
  State<_MultiSheet> createState() => _MultiSheetState();
}

class _MultiSheetState extends State<_MultiSheet> {
  late Set<int> sel = {...widget.initial};
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final e in widget.items)
                CheckboxListTile(
                  value: sel.contains(e.$1), title: Text(e.$2), controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => v == true ? sel.add(e.$1) : sel.remove(e.$1)),
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(20), child: PillButton(tr('done'), onPressed: () => Navigator.pop(context, sel))),
        ]),
      ),
    );
  }
}

Future<String?> inputSheet(BuildContext c,
    {required String title, String? label, String initial = '', TextInputType? type, int maxLines = 1, String? action}) {
  final ctrl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: c, isScrollControlled: true, showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(c).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(controller: ctrl, autofocus: true, keyboardType: type, maxLines: maxLines, minLines: maxLines > 1 ? 3 : 1, decoration: InputDecoration(hintText: label)),
        const SizedBox(height: 16),
        PillButton(action ?? tr('save'), onPressed: () => Navigator.pop(c, ctrl.text.trim())),
      ]),
    ),
  );
}

Future<bool> confirmDialog(BuildContext c, String title, String body, {bool danger = false, String? yes}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title), content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(shape: const StadiumBorder(), backgroundColor: danger ? Theme.of(c).colorScheme.error : null),
          onPressed: () => Navigator.pop(c, true), child: Text(yes ?? tr('yes')),
        ),
      ],
    ),
  );
  return r == true;
}

// ---------------------------------------------------------------- files, gps, contact
Future<List<String>> pickImages(BuildContext c, {bool multi = true}) async {
  final src = await pickSheet<int>(c, tr('add_photo'), [(1, tr('camera')), (2, tr('gallery'))]);
  if (src == null) return [];
  try {
    final p = ImagePicker();
    if (src == 1) {
      final f = await p.pickImage(source: ImageSource.camera, imageQuality: 85);
      return f == null ? [] : [f.path];
    }
    if (multi) return [for (final f in await p.pickMultiImage(imageQuality: 85)) f.path];
    final f = await p.pickImage(source: ImageSource.gallery, imageQuality: 85);
    return f == null ? [] : [f.path];
  } catch (_) {
    toast(c, tr('err_generic'));
    return [];
  }
}

Future<String?> pickDocument(BuildContext c, {bool images = true}) async {
  try {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', if (images) ...['jpg', 'jpeg', 'png', 'webp']],
    );
    return r?.files.single.path;
  } catch (_) {
    toast(c, tr('err_generic'));
    return null;
  }
}

Future<Position> getPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw ApiError(-1, 'gps_required');
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw ApiError(-1, 'gps_required');
  return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)));
}

Future<void> openUri(BuildContext c, Uri u) async {
  try {
    if (!await launchUrl(u, mode: LaunchMode.externalApplication)) toast(c, tr('err_generic'));
  } catch (_) {
    toast(c, tr('err_generic'));
  }
}

String _digits(String p) => p.replaceAll(RegExp(r'[^\d]'), '');
Uri telUri(String p) => Uri(scheme: 'tel', path: p.replaceAll(' ', ''));
Uri smsUri(String p) => Uri(scheme: 'sms', path: p.replaceAll(' ', ''));
Uri waUri(String p) => Uri.parse('https://wa.me/${_digits(p)}');
Uri mapsUri(num lat, num lng) => Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

class ContactRow extends StatelessWidget {
  final String phone;
  final VoidCallback? onChat;
  const ContactRow(this.phone, {super.key, this.onChat});
  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, String l, VoidCallback f) => OutlinedButton.icon(
          onPressed: f, icon: Icon(i, size: 18), label: Text(l),
          style: OutlinedButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(0, 42), side: BorderSide(color: Theme.of(context).colorScheme.outline)),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (onChat != null) b(Icons.chat_bubble_outline, tr('chat'), onChat!),
      b(Icons.call_outlined, tr('call'), () => openUri(context, telUri(phone))),
      b(Icons.forum_outlined, 'WhatsApp', () => openUri(context, waUri(phone))),
      b(Icons.sms_outlined, 'SMS', () => openUri(context, smsUri(phone))),
    ]);
  }
}

// ---------------------------------------------------------------- location popups
Future<Map<String, dynamic>?> pickLocation(BuildContext c, {bool wholeDistrict = false}) async {
  final regions = await busyVal<List>(c, () async => await Api.get('/locations/regions') as List);
  if (regions == null || !c.mounted) return null;
  final rid = await pickSheet<int>(c, tr('region'), [for (final r in regions) (r['id'] as int, r['name'] as String)], search: true);
  if (rid == null || !c.mounted) return null;
  final region = regions.firstWhere((r) => r['id'] == rid);
  final ds = await busyVal<List>(c, () async => await Api.get('/locations/districts?region_id=$rid') as List);
  if (ds == null || !c.mounted) return null;
  if (ds.isEmpty) {
    toast(c, tr('no_districts'));
    return null;
  }
  final did = await pickSheet<int>(c, tr('district'), [for (final d in ds) (d['id'] as int, d['name'] as String)], search: true);
  if (did == null || !c.mounted) return null;
  final district = ds.firstWhere((d) => d['id'] == did);
  final ws = await busyVal<List>(c, () async => await Api.get('/locations/wards?district_id=$did') as List);
  if (ws == null || !c.mounted) return null;
  int? wid;
  String? wname;
  if (ws.isNotEmpty) {
    final items = <(int, String)>[if (wholeDistrict) (0, tr('whole_district')), for (final w in ws) (w['id'] as int, w['name'] as String)];
    final pick = await pickSheet<int>(c, tr('ward'), items, search: true);
    if (pick == null) return null;
    if (pick != 0) {
      wid = pick;
      wname = ws.firstWhere((w) => w['id'] == pick)['name'] as String;
    }
  }
  return {
    'region_id': rid, 'district_id': did, 'ward_id': wid,
    'region_name': region['name'], 'district_name': district['name'], 'ward_name': wname,
    'active': region['active'] == true && district['active'] == true,
    'label': [wname, district['name'], region['name']].whereType<String>().join(', '),
  };
}
