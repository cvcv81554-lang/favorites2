import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

import '../../../data/keys.dart';
import '../../../data/studio_repo.dart';
import '../../../domain/performer.dart';
import '../../core/net_image.dart';
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
    final net = await ApiKeys.has(ApiKeys.stash), tp = await ApiKeys.has(ApiKeys.tpdb);
    state = AsyncData(s.copy(busy: true, err: '', msg: 'بدء الاكتشاف…'));
    try {
      final n = await r.discover(lib, network: net, tpdb: tp, progress: (m) => state = AsyncData(s.copy(msg: m)));
      state = AsyncData(s.copy(imgs: await r.all(), last: DateTime.now().millisecondsSinceEpoch, busy: false, msg: '', err: net || tp ? '' : 'أضيفت صور المشاهد فقط — أضيفي مفتاح StashDB أو ThePornDB لصور الممثلات.'));
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

/// تبويبات الاستديو — كل تبويب له سطر يشرحه.
const studioTabs = <(String, IconData, String)>[
  ('جديد', Icons.fiber_new_rounded, 'صور أُضيفت منذ زيارتك السابقة، الأحدث أولًا'),
  ('الكل', Icons.photo_library_rounded, 'كل صور ممثلات مكتبتك · الأعلى دقة أولًا'),
  ('المفضلة', Icons.favorite_rounded, 'الصور التي ضغطتِ عليها ♥ (في العارض أو بالضغط المطوّل)'),
  ('الألبومات', Icons.collections_rounded, 'مجموعات تتكوّن وحدها حسب الدقة والنوع والمصدر'),
  ('الممثلات', Icons.people_alt_rounded, 'صور كل ممثلة في مكان واحد'),
];

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});
  @override ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  int? _tab;   // يُختار تلقائيًا أول مرة: «جديد» إن وُجد جديد، وإلا «الكل»

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(studioProvider).value ?? const StudioState();
    final lib = {for (final p in ref.watch(libraryProvider).value ?? const <Performer>[]) p.id: p};
    final imgs = st.imgs.where((x) => lib.containsKey(x.pid)).toList();     // صور ممثلات المكتبة الحالية فقط (والبوابة مطبقة على المكتبة)
    final fresh = (imgs.where((x) => st.since > 0 && x.found > st.since).toList()..sort((a, b) => b.found.compareTo(a.found)));
    final liked = imgs.where((x) => x.like).toList()..sort((a, b) => b.found.compareTo(a.found));
    final all = [...imgs]..sort((a, b) => b.longSide != a.longSide ? b.longSide.compareTo(a.longSide) : b.found.compareTo(a.found));
    final byP = <String, List<StudioImg>>{}; for (final x in imgs) { (byP[x.pid] ??= []).add(x); }
    final tab = _tab ?? (fresh.isNotEmpty ? 0 : 1);
    final counts = [fresh.length, imgs.length, liked.length, smartAlbums.values.where((a) => imgs.any(a.$2)).length + 1, byP.length];
    final n = ref.read(studioProvider.notifier);

    final header = SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الاستديو', style: Theme.of(context).textTheme.headlineSmall),
          Text('معرض صور ممثلات مكتبتك · ${imgs.length} صورة · ${byP.length} ممثلة', style: const TextStyle(color: C.muted, fontSize: 13)),
        ])),
      ]),
      const SizedBox(height: S.s3),
      // زر الاكتشاف واضح وكبير مع حالة التقدم وآخر تحديث
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: st.busy ? null : n.discover,
        icon: st.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore_rounded),
        label: Text(st.busy ? st.msg : 'ابحثي عن صور جديدة'))),
      if (!st.busy && st.last > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('آخر بحث: ${_ago(st.last)} · من StashDB وThePornDB وصور المشاهد', style: const TextStyle(color: C.muted, fontSize: 12))),
      if (st.err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s2), child: Row(children: [
        Expanded(child: Text(st.err, style: const TextStyle(color: C.muted))),
        if (st.err.contains('مفتاح')) TextButton.icon(onPressed: () => context.go('/more'), icon: const Icon(Icons.key_rounded), label: const Text('المفاتيح')),
      ])),
    ])));

    if (imgs.isEmpty && !st.busy) {
      return Scaffold(body: SafeArea(bottom: false, child: CustomScrollView(slivers: [header,
        SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'معرضك الخاص فارغ',
          body: 'اضغطي «ابحثي عن صور جديدة» ليجمع الاستديو صور ممثلات مكتبتك (من StashDB وThePornDB) وصور مشاهدهن.\n\nبعدها تجدين:\n• جديد — ما أُضيف منذ زيارتك\n• المفضلة — ما أعجبك ♥\n• الألبومات والممثلات — ترتيب تلقائي\n\nكل الصور تبقى على جهازك.')),
      ])));
    }

    // شريط التبويبات (مثبّت أعلى الصفحة)
    final tabs = SliverPersistentHeader(pinned: true, delegate: _TabsBar(height: 52, child: Container(color: C.bg, child: ListView.separated(
      scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: 8), itemCount: studioTabs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (c, i) => ChoiceChip(
        selected: tab == i, showCheckmark: false, avatar: Icon(studioTabs[i].$2, size: 18),
        label: Text('${studioTabs[i].$1}${counts[i] > 0 ? ' ${counts[i]}' : ''}'),
        onSelected: (_) => setState(() => _tab = i))))));
    final hint = SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, 4, S.s4, S.s2), child: Text(studioTabs[tab].$3, style: const TextStyle(color: C.muted, fontSize: 12.5))));

    final body = switch (tab) {
      0 => fresh.isEmpty ? _empty('لا جديد منذ زيارتك', 'اضغطي «ابحثي عن صور جديدة» أعلاه. ستظهر هنا الصور التي تُضاف من الآن.') : _grid(context, fresh, lib, 'new'),
      1 => _grid(context, all, lib, 'all'),
      2 => liked.isEmpty ? _empty('لا صور مفضلة بعد', 'افتحي أي صورة واضغطي ♥ أعلى الشاشة، أو اضغطي مطولًا على الصورة في الشبكة.') : _grid(context, liked, lib, 'liked'),
      3 => _albums(context, imgs, lib),
      _ => _performers(context, byP, lib),
    };
    return Scaffold(body: SafeArea(bottom: false, child: RefreshIndicator(onRefresh: n.discover, child: CustomScrollView(slivers: [header, tabs, hint, body, const SliverToBoxAdapter(child: SizedBox(height: 140))]))));
  }

  Widget _empty(String t, String b) => SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: t, body: b));

  /// شبكة صور: اسم الممثلة على كل صورة، ♥ للمفضلة، نقطة للصور التي لم تُفتح، والضغط المطوّل يبدّل المفضلة.
  Widget _grid(BuildContext context, List<StudioImg> l, Map<String, Performer> lib, String tag) => SliverPadding(padding: const EdgeInsets.symmetric(horizontal: S.s2),
    sliver: SliverGrid.builder(itemCount: l.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 600 ? 140 : 210, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 3 / 4),
      itemBuilder: (c, i) => _Tile(x: l[i], name: lib[l[i].pid]?.name ?? '', onTap: () => openViewer(c, l, i, lib))));

  Widget _albums(BuildContext context, List<StudioImg> imgs, Map<String, Performer> lib) {
    final d = DateTime.now();
    final albums = <(String, String, List<StudioImg>)>[
      ('☀️ مختارات اليوم', 'تتجدد كل يوم', ([...imgs]..shuffle(Random(d.year * 1000 + d.month * 40 + d.day))).take(24).toList()),
      for (final e in smartAlbums.entries) (e.value.$1, '', imgs.where(e.value.$2).toList()),
    ].where((a) => a.$3.isNotEmpty).toList();
    return SliverPadding(padding: const EdgeInsets.symmetric(horizontal: S.s4), sliver: SliverGrid.builder(itemCount: albums.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3, childAspectRatio: .82),
      itemBuilder: (c, i) { final a = albums[i];
        return Semantics(button: true, label: a.$1, child: InkWell(borderRadius: BorderRadius.circular(S.rLg), onTap: () => _openGrid(c, a.$1, a.$3, lib), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 2, child: Photo(a.$3.first.thumb, alignment: Alignment.center)),
            if (a.$3.length > 2) ...[const SizedBox(width: 2), Expanded(child: Column(children: [Expanded(child: Photo(a.$3[1].thumb, alignment: Alignment.center)), const SizedBox(height: 2), Expanded(child: Photo(a.$3[2].thumb, alignment: Alignment.center))]))],
          ]))),
          const SizedBox(height: 6),
          Text(a.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${a.$3.length} صورة${a.$2.isEmpty ? '' : ' · ${a.$2}'}', style: const TextStyle(color: C.muted, fontSize: 12)),
        ]))); }));
  }

  Widget _performers(BuildContext context, Map<String, List<StudioImg>> byP, Map<String, Performer> lib) {
    final l = (byP.entries.where((e) => lib[e.key] != null).toList()..sort((a, b) => b.value.length.compareTo(a.value.length)));
    return SliverList.separated(itemCount: l.length, separatorBuilder: (_, _) => const Divider(height: 1, indent: S.s4, endIndent: S.s4, color: C.line),
      itemBuilder: (c, i) { final p = lib[l[i].key]!; final ph = (l[i].value..sort((a, b) => b.longSide.compareTo(a.longSide)));
        final liked = ph.where((x) => x.like).length, unseen = ph.where((x) => x.seen == 0).length;
        return InkWell(onTap: () => _openGrid(c, p.name, ph, lib, pid: p.id), child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s2), child: Row(children: [
          SizedBox(width: 56, height: 56, child: ClipOval(child: Photo(p.cover, name: p.name, fallbacks: p.coverFallbacks))),
          const SizedBox(width: S.s3),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(['${ph.length} صورة', if (liked > 0) '$liked ♥', if (unseen > 0) '$unseen لم تُفتح'].join(' · '), style: const TextStyle(color: C.muted, fontSize: 12.5)),
          ])),
          for (final x in ph.take(3)) Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 40, height: 52, child: Photo(x.thumb, alignment: Alignment.center)))),
        ])));
      });
  }

  static void _openGrid(BuildContext context, String title, List<StudioImg> l, Map<String, Performer> lib, {String? pid}) => Navigator.of(context).push(MaterialPageRoute(builder: (c) => Scaffold(
    appBar: AppBar(title: Text(title), actions: [if (pid != null) TextButton.icon(onPressed: () { Navigator.pop(c); context.push('/p/$pid'); }, icon: const Icon(Icons.person_rounded), label: const Text('ملفها'))]),
    body: Consumer(builder: (c, ref, _) { ref.watch(studioProvider);   // يتحدّث ♥ فورًا
      return GridView.builder(padding: const EdgeInsets.all(S.s2), itemCount: l.length,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: MediaQuery.sizeOf(c).width < 600 ? 140 : 210, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 3 / 4),
        itemBuilder: (c, i) => _Tile(x: l[i], name: pid != null ? '' : lib[l[i].pid]?.name ?? '', onTap: () => openViewer(c, l, i, lib))); }),
  )));
}

String _ago(int ms) {
  final m = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inMinutes;
  return m < 1 ? 'الآن' : m < 60 ? 'قبل $m د' : m < 1440 ? 'قبل ${m ~/ 60} س' : 'قبل ${m ~/ 1440} يوم';
}

class _TabsBar extends SliverPersistentHeaderDelegate {
  _TabsBar({required this.height, required this.child});
  final double height; final Widget child;
  @override double get minExtent => height;
  @override double get maxExtent => height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override bool shouldRebuild(_TabsBar old) => true;
}

/// خلية صورة: الصورة كاملة الوضوح لحجمها + اسم الممثلة + ♥ + نقطة «لم تُفتح». الضغط المطوّل يبدّل المفضلة.
class _Tile extends ConsumerWidget {
  const _Tile({required this.x, required this.name, required this.onTap});
  final StudioImg x; final String name; final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(button: true, label: '$name${x.like ? ' · مفضلة' : ''}', child: GestureDetector(
    onTap: onTap,
    onLongPress: () { HapticFeedback.selectionClick(); ref.read(studioProvider.notifier).toggleLike(x);
      ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 1), content: Text(x.like ? 'أُضيفت للمفضلة ♥' : 'أُزيلت من المفضلة'))); },
    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Stack(fit: StackFit.expand, children: [
      Photo(x.kind == 'still' ? x.wide : x.thumb, alignment: x.kind == 'still' ? Alignment.center : const Alignment(0, -.4)),
      if (name.isNotEmpty) Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)))),
      if (x.like) const Positioned(top: 4, left: 4, child: Icon(Icons.favorite_rounded, color: C.rose, size: 18, shadows: [Shadow(blurRadius: 4)])),
      if (x.seen == 0) Positioned(top: 6, right: 6, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.gold, shape: BoxShape.circle))),
    ]))));
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
    for (final j in [i - 1, i + 1]) { if (j >= 0 && j < widget.l.length && widget.l[j].url.startsWith('https://')) precacheImage(netImage(widget.l[j].url), context); }
    ref.read(studioProvider.notifier).markSeen(widget.l[i]);
  }
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch(_i));
    final x = widget.l[_i]; final p = widget.lib[x.pid];
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      PageView.builder(controller: _pc, itemCount: widget.l.length, onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (c, i) => InteractiveViewer(minScale: 1, maxScale: 5, child: Center(child: Photo(widget.l[i].url, fit: BoxFit.contain, alignment: Alignment.center, full: true, fallbacks: [StudioImg.sized(widget.l[i].url, 1280)])))),
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
