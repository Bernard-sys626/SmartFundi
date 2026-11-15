import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import 'package:provider/provider.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'shared.dart';

/// Pictures and short videos the Admin uploaded for a place in the app ('home', 'help_client', 'help_fundi').
Future<List<J>> loadMedia(String placement) async => asList(await Api.get('/media?placement=$placement'));

/// Swiping banner for the Home page. Shows nothing when the Admin has not uploaded anything.
class MediaCarousel extends StatefulWidget {
  final String placement;
  final double height;
  const MediaCarousel({super.key, this.placement = 'home', this.height = 170});
  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  List<J> _items = [];
  final _ctrl = PageController(viewportFraction: .92);
  Timer? _t;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    loadMedia(widget.placement).then((v) {
      if (!mounted) return;
      setState(() => _items = v);
      if (v.length > 1) {
        _t = Timer.periodic(const Duration(seconds: 6), (_) {
          if (!mounted || !_ctrl.hasClients) return;
          _ctrl.animateToPage((_i + 1) % _items.length, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _t?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _ctrl, itemCount: _items.length, onPageChanged: (i) => _i = i,
            itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: MediaTile(_items[i], height: widget.height)),
          ),
        ),
        if (_items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _items.length; i++)
                Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _i ? brandOrange : Colors.grey.withOpacity(.4))),
            ]),
          ),
      ]),
    );
  }
}

/// One picture (tap = full screen) or one video (tap = plays in the phone's player).
class MediaTile extends StatelessWidget {
  final J m;
  final double height;
  const MediaTile(this.m, {super.key, this.height = 170});
  @override
  Widget build(BuildContext context) {
    final video = m['kind'] == 'video';
    final title = (m['title'] ?? '').toString();
    return GestureDetector(
      onTap: () => video ? openFile(context, m['file_id'] as String) : showPhoto(context, m['file_id'] as String),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(fit: StackFit.expand, children: [
          if (video)
            Container(decoration: const BoxDecoration(gradient: brandGradient), child: const Center(child: Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white)))
          else
            FileImg(m['file_id'] as String, h: height, radius: 0, thumb: 900),
          if (title.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xAA000000)])),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Help for [kind] 'client' or 'fundi': numbered steps (including how to pay), then the videos the Admin uploaded.
class HelpPage extends StatelessWidget {
  final String kind;
  const HelpPage({super.key, required this.kind});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = kind == 'fundi' ? 'hf' : 'hc';
    final steps = <(String, String)>[];
    for (var i = 1; hasTr('${p}${i}_t'); i++) {
      steps.add((tr('${p}${i}_t'), tr('${p}${i}_b')));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('help'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        HeroCard(child: Row(children: [
          const Icon(Icons.help_outline, size: 36),
          const SizedBox(width: 14),
          Expanded(child: Text(tr(kind == 'fundi' ? 'help_fundi_intro' : 'help_client_intro'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
        ])),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++)
          AppCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 15, backgroundColor: brandOrange, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(steps[i].$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(steps[i].$2, style: TextStyle(color: cs.secondary, height: 1.4)),
              ])),
            ]),
          ),
        const SizedBox(height: 8),
        FutureBuilder<List<J>>(
          future: loadMedia(kind == 'fundi' ? 'help_fundi' : 'help_client'),
          builder: (c, snap) {
            final items = snap.data ?? [];
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle(tr('help_videos')),
              for (final m in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(height: 180, child: MediaTile(m, height: 180))),
            ]);
          },
        ),
        const SizedBox(height: 8),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('still_need_help'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('contact_us_sub'), style: TextStyle(color: cs.secondary)),
            const SizedBox(height: 10),
            for (final ph in context.read<AppState>().supportPhones) Padding(padding: const EdgeInsets.only(bottom: 8), child: ContactRow(ph)),
          ]),
        ),
      ]),
    );
  }
}
