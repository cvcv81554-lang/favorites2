import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/keys.dart';
import '../../../data/studio_repo.dart';
import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class StudioState { final List<StudioImg> imgs; final int since, last; final bool busy; final String msg, err;
  const StudioState({this.imgs = const [], this.since = 0, this.last = 0, this.busy = false, this.msg = '', this.err = ''});
  StudioState copy({List<StudioImg>? imgs, int? since, int? last, bool? busy, String? msg, String? err}) => StudioState(imgs: imgs ?? this.imgs, since: since ?? this.since, last: last ?? this.last, busy: busy ?? this.busy, msg: msg ?? this.msg, err: err ?? this.err); }

final studioRepoProvider = FutureProvider<StudioRepo>((ref) => StudioRepo.open());

class Studio extends AsyncNotifier<StudioState> {
  @override
  Future<StudioState> build() async {
    final r = await ref.watch(studioRepoProvider.future);
    if (kIsWeb && Uri.base.queryParameters['demo'] == '1') return StudioState(imgs: _demo(), since: DateTime.now().millisecondsSinceEpoch - 86400000);
    final prev = (await r.kvGet('visit') as num?)?.toInt() ?? 0;
    await r.kvSet('visit', DateTime.now().millisecondsSinceEpoch);   // «جديد منذ زيارتك» يبقى طوال هذه الجلسة
    return StudioState(imgs: await r.all(), since: prev, last: (await r.kvGet('last') as num?)?.toInt() ?? 0);
  }
  StudioState get s => state.value ?? const StudioState();

  Future<void> discover() async {
    if (s.busy) return;
    final r = await ref.read(studioRepoProvider.future);
    final lib = ref.read(libraryProvider).value ?? const <Performer>[];
    final net = await ApiKeys.has(ApiKeys.stash);
    state = AsyncData(s.copy(busy: true, err: '', msg: 'بدء الاكتشاف…'));
    try {
      final n = await r.discover(lib, network: net, progress: (m) => state = AsyncData(s.copy(msg: m)));
      state = AsyncData(s.copy(imgs: await r.all(), last: DateTime.now().millisecondsSinceEpoch, busy: false, msg: '', err: net ? '' : 'أضيفت صور المشاهد فقط — أضف مفتاح StashDB لصور الممثلات.'));
      if (n == 0 && s.err.isEmpty) state = AsyncData(s.copy(err: 'لا صور جديدة الآن.'));
    } catch (e) { state = AsyncData(s.copy(busy: false, msg: '', err: '$e')); }
  }

  Future<void> toggleLike(StudioImg x) async { x.like = !x.like; await (await ref.read(studioRepoProvider.future)).put([x]); state = AsyncData(s.copy(imgs: [...s.imgs])); }
  Future<void> markSeen(StudioImg x) async { if (x.seen > 0) return; x.seen = DateTime.now().millisecondsSinceEpoch; await (await ref.read(studioRepoProvider.future)).put([x]); }

  static List<StudioImg> _demo() { final now = DateTime.now().millisecondsSinceEpoch; return [for (var i = 0; i < 60; i++) StudioImg(id: 'd$i', pid: 'demo-${1 + i % 18}', url: 'https://img.test/${i % 3 == 0 ? 'w' : 'p'}${i % (i % 3 == 0 ? 6 : 12)}.png', src: ['stash', 'scene', 'tpdb'][i % 3], kind: i % 3 == 0 ? 'still' : 'portrait', w: i % 4 == 0 ? 4000 : 1200, h: i % 4 == 0 ? 6000 : 1800, found: now - i * 3600000 * 3, like: i % 7 == 0)]; }
}
final studioProvider = AsyncNotifierProvider<Studio, StudioState>(Studio.new);

/// الألبومات الذكية: تتجمّع وحدها.
final smartAlbums = <String, (String, bool Function(StudioImg))>{
  '4k': ('دقة 4K وأعلى', (x) => x.longSide >= 3000),
  'hd': ('عالية الدقة', (x) => x.longSide >= 1500 && x.longSide < 3000),
  'portrait': ('بورتريهات', (x) => x.kind == 'portrait'),
  'still': ('لقطات المشاهد', (x) => x.kind == 'still'),
  'stash': ('من StashDB', (x) => x.src == 'stash'),
  'unseen': ('لم تريها بعد', (x) => x.seen == 0),
  'liked': ('أعجبتني', (x) => x.like),
};

class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studioProvider).value ?? const StudioState();
    final lib = {for (final p in ref.watch(libraryProvider).value ?? const <Performer>[]) p.id: p};
    final imgs = st.imgs.where((x) => lib.containsKey(x.pid)).toList();     // صور ممثلات المكتبة الحالية فقط (والبوابة مطبقة على المكتبة)
    final fresh = (imgs.where((x) => st.since > 0 && x.found > st.since).toList()..sort((a, b) => b.found.compareTo(a.found)));
    final d = DateTime.now(); final daily = [...imgs]..shuffle(Random(d.year * 1000 + d.month * 40 + d.day));
    final byP = <String, List<StudioImg>>{}; for (final x in imgs) { (byP[x.pid] ??= []).add(x); }
    final topP = (byP.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))).take(6).toList();
    return Scaffold(body: SafeArea(bottom: false, child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الاستديو', style: Theme.of(context).textTheme.headlineSmall),
          Text(st.busy ? st.msg : '${imgs.length} صورة · ${byP.length} ممثلة', style: const TextStyle(color: C.muted)),
        ])),
        IconButton.filledTonal(tooltip: 'اكتشاف صور جديدة', onPressed: st.busy ? null : () => ref.read(studioProvider.notifier).discover(), icon: st.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded)),
      ]))),
      if (st.err.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: Text(st.err, style: const TextStyle(color: C.muted)))),
      if (imgs.isEmpty && !st.busy)
        SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'معرضك الخاص', body: 'يجمع صور ممثلات مكتبتك من StashDB وصور مشاهدها، ويرتبها في ألبومات ذكية.\nكل الصور تبقى على جهازك.',
          actions: [FilledButton.icon(onPressed: () => ref.read(studioProvider.notifier).discover(), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('ابدأ الاكتشاف'))]))
      else ...[
        if (fresh.isNotEmpty) _strip(context, '🆕 جديد منذ زيارتك', '${fresh.length} صورة', fresh, lib),
        _strip(context, '☀️ مختارات اليوم', 'تتجدد كل يوم', daily.take(16).toList(), lib),
        SliverToBoxAdapter(child: SectionHeader('ألبومات ذكية', sub: 'تتجمّع وحدها حسب الدقة والنوع والمصدر')),
        SliverToBoxAdapter(child: SizedBox(height: 132, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), children: [
          for (final e in smartAlbums.entries) () {
            final l = imgs.where(e.value.$2).toList(); if (l.isEmpty) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsetsDirectional.only(end: S.s3), child: InkWell(borderRadius: BorderRadius.circular(S.rLg), onTap: () => _openGrid(context, e.value.$1, l, lib), child: SizedBox(width: 170, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final x in l.take(2)) Expanded(child: Photo(x.thumb, cacheWidth: 240))]))),
              const SizedBox(height: 4), Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)), Text('${l.length} صورة', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]))));
          }(),
        ]))),
        for (final e in topP) if (lib[e.key] != null) _strip(context, lib[e.key]!.name, '${e.value.length} صورة', (e.value..sort((a, b) => b.longSide.compareTo(a.longSide))).take(20).toList(), lib),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 140)),
    ])));
  }

  Widget _strip(BuildContext context, String t, String sub, List<StudioImg> l, Map<String, Performer> lib) => SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(t, sub: sub, action: l.length > 6 ? 'الكل' : null, onAction: () => _openGrid(context, t, l, lib)),
    SizedBox(height: 190, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), itemCount: l.length,
      separatorBuilder: (_, _) => const SizedBox(width: S.s2),
      itemBuilder: (c, i) => GestureDetector(onTap: () => openViewer(c, l, i, lib), child: ClipRRect(borderRadius: BorderRadius.circular(S.rMd),
        child: SizedBox(width: l[i].kind == 'still' ? 240 : 140, child: Hero(tag: 'si-${l[i].id}-$t', child: Photo(l[i].thumb, cacheWidth: 400))))))),
  ]));

  static void _openGrid(BuildContext context, String title, List<StudioImg> l, Map<String, Performer> lib) => Navigator.of(context).push(MaterialPageRoute(builder: (c) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: GridView.builder(padding: const EdgeInsets.all(S.s2), itemCount: l.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: MediaQuery.sizeOf(c).width < 600 ? 130 : 200, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 3 / 4),
      itemBuilder: (c, i) => GestureDetector(onTap: () => openViewer(c, l, i, lib), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Photo(l[i].thumb, cacheWidth: 300)))),
  )));
}

/// العارض: ملء الشاشة، تكبير بالقرص، سحب، إعجاب، وتحميل الصورتين المجاورتين مسبقًا.
void openViewer(BuildContext context, List<StudioImg> l, int i, Map<String, Performer> lib) => Navigator.of(context).push(PageRouteBuilder(opaque: false, barrierColor: Colors.black,
  transitionDuration: S.med, pageBuilder: (c, a, _) => FadeTransition(opacity: a, child: _Viewer(l: l, start: i, lib: lib))));

class _Viewer extends ConsumerStatefulWidget {
  const _Viewer({required this.l, required this.start, required this.lib});
  final List<StudioImg> l; final int start; final Map<String, Performer> lib;
  @override ConsumerState<_Viewer> createState() => _ViewerState();
}
class _ViewerState extends ConsumerState<_Viewer> {
  late final _pc = PageController(initialPage: widget.start);
  late int _i = widget.start;
  @override void dispose() { _pc.dispose(); super.dispose(); }
  void _prefetch(int i) {
    for (final j in [i - 1, i + 1]) { if (j >= 0 && j < widget.l.length && widget.l[j].url.startsWith('https://')) precacheImage(NetworkImage(StudioImg.sized(widget.l[j].url, 1280)), context); }
    ref.read(studioProvider.notifier).markSeen(widget.l[i]);
  }
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch(_i));
    final x = widget.l[_i]; final p = widget.lib[x.pid];
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      PageView.builder(controller: _pc, itemCount: widget.l.length, onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (c, i) => InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: Photo(StudioImg.sized(widget.l[i].url, 1280), fit: BoxFit.contain, alignment: Alignment.center)))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(S.s2), child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        Expanded(child: Text(p?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        Text('${_i + 1} / ${widget.l.length}', style: const TextStyle(color: Colors.white70)),
        IconButton(onPressed: () { ref.read(studioProvider.notifier).toggleLike(x); setState(() {}); }, icon: Icon(x.like ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: x.like ? C.rose : Colors.white)),
      ]))),
      if (x.w > 0) Positioned(bottom: 24, left: 0, right: 0, child: Center(child: Text('${x.w}×${x.h} · ${x.src == 'stash' ? 'StashDB' : x.src == 'scene' ? 'لقطة مشهد' : x.src}', style: const TextStyle(color: Colors.white54, fontSize: 12)))),
    ]));
  }
}
