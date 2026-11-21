import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/performer.dart';
import '../../../domain/sanitize.dart';
import '../../../domain/works.dart';
import '../../core/posters.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../tools/lists_state.dart';
import '../tools/tools_screen.dart' show askName;

final worksProvider = Provider<List<WorkGroup>>((ref) => groupWorks(ref.watch(libraryProvider).value ?? const []));

enum WTab { recent, watch, upcoming, seen, top, diary, performers, studios }

/// كل تبويب: اسمه، أيقونته، وسطر يشرحه.
const workTabs = <WTab, (String, IconData, String)>{
  WTab.recent: ('الأحدث', Icons.new_releases_rounded, 'أعمال صدرت، الأحدث أولًا'),
  WTab.watch: ('للمشاهدة', Icons.bookmark_rounded, 'ما حفظتِه لتشاهديه لاحقًا · اضغطي 🔖 على أي عمل'),
  WTab.upcoming: ('القادمة', Icons.event_rounded, 'إصدارات لم تصدر بعد، مع العدّ التنازلي'),
  WTab.seen: ('شاهدتها', Icons.check_circle_rounded, 'كل ما علّمتِه «شاهدته»'),
  WTab.top: ('الأعلى تقييمًا', Icons.star_rounded, 'أعمال قيّمتِها 4 نجوم فأكثر'),
  WTab.diary: ('يومياتي', Icons.menu_book_rounded, 'سجل مشاهداتك بالتاريخ، شهرًا بشهر'),
  WTab.performers: ('حسب الممثلة', Icons.people_alt_rounded, 'تقدّمك في أعمال كل ممثلة'),
  WTab.studios: ('الاستوديوهات', Icons.business_rounded, 'الأعمال مجمّعة حسب الاستوديو'),
};

enum WSort { date, rating, title }

class _WState {
  final WTab tab; final String q; final String wl; final bool grid; final WSort sort; final String studio;
  const _WState(this.tab, this.q, [this.wl = '', this.grid = true, this.sort = WSort.date, this.studio = '']);
  _WState copy({WTab? tab, String? q, String? wl, bool? grid, WSort? sort, String? studio}) => _WState(tab ?? this.tab, q ?? this.q, wl ?? this.wl, grid ?? this.grid, sort ?? this.sort, studio ?? this.studio);
}
class _WN extends Notifier<_WState> {
  @override _WState build() {
    // لقطات الويب التجريبية فقط (?demo=1&wt=رقم): فتح تبويب مباشرة
    final wt = kIsWeb && Uri.base.queryParameters['demo'] == '1' ? int.tryParse(Uri.base.queryParameters['wt'] ?? '') : null;
    return _WState(wt != null && wt >= 0 && wt < WTab.values.length ? WTab.values[wt] : WTab.recent, '');
  } void set(_WState s) => state = s; }
final _wProvider = NotifierProvider<_WN, _WState>(_WN.new);

/// تحديد متعدد للأعمال (ضغط مطوّل) لإجراء جماعي.
class _SelN extends Notifier<Set<String>> { @override Set<String> build() => {}; void toggle(String k) => state = state.contains(k) ? ({...state}..remove(k)) : {...state, k}; void clear() => state = {}; }
final _selProvider = NotifierProvider<_SelN, Set<String>>(_SelN.new);

/// مركز الأعمال: «شاهدي التالي» + تبويبات واضحة + عرض شبكة/قائمة + ترتيب + قوائمك + تقدّمك لكل ممثلة واستوديو.
class WorksScreen extends ConsumerWidget {
  const WorksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(worksProvider);
    final st = ref.watch(_wProvider);
    final n = ref.read(_wProvider.notifier);
    final t0 = todayStr();
    final q = norm(st.q);
    Iterable<WorkGroup> l = all;
    if (st.wl.isNotEmpty) l = l.where((g) => g.ls.contains(st.wl));
    if (st.studio.isNotEmpty) l = l.where((g) => norm(g.s) == norm(st.studio));
    if (q.isNotEmpty) l = l.where((g) => norm('${g.t} ${g.s} ${g.who.map((p) => p.name).join(' ')}').contains(q));
    final released = l.where((g) => !g.isUpcoming && g.date.isNotEmpty && g.date.compareTo(t0) <= 0);
    var list = switch (st.tab) {
      WTab.recent => released.toList(),
      WTab.watch => (l.where((g) => g.q && !g.seen).toList()..sort((a, b) => b.a.compareTo(a.a))),
      WTab.upcoming => (l.where((g) => g.isUpcoming).toList()..sort((a, b) => a.date.compareTo(b.date))),
      WTab.seen => (l.where((g) => g.seen).toList()..sort((a, b) => b.wd.compareTo(a.wd))),
      WTab.top => (l.where((g) => g.r >= 4).toList()..sort((a, b) => b.r.compareTo(a.r))),
      WTab.diary => (l.where((g) => g.seen && g.wd.isNotEmpty).toList()..sort((a, b) => b.wd.compareTo(a.wd))),
      _ => l.toList(),
    };
    if (st.tab == WTab.recent || (st.sort != WSort.date && st.tab != WTab.upcoming && st.tab != WTab.diary)) {
      switch (st.sort) {
        case WSort.date: list.sort((a, b) => b.date.compareTo(a.date));
        case WSort.rating: list.sort((a, b) => b.r != a.r ? b.r.compareTo(a.r) : b.date.compareTo(a.date));
        case WSort.title: list.sort((a, b) => a.t.toLowerCase().compareTo(b.t.toLowerCase()));
      }
    }
    final seen = all.where((g) => g.seen).length;
    final watchN = all.where((g) => g.q && !g.seen).length, upN = all.where((g) => g.isUpcoming).length;
    final counts = {WTab.recent: all.where((g) => !g.isUpcoming && g.date.isNotEmpty && g.date.compareTo(t0) <= 0).length, WTab.watch: watchN, WTab.upcoming: upN, WTab.seen: seen,
      WTab.top: all.where((g) => g.r >= 4).length, WTab.diary: all.where((g) => g.seen && g.wd.isNotEmpty).length};
    // «شاهدي التالي»: أقدم ما حُفظ للمشاهدة (أو الأحدث صدورًا ولم يُشاهد)، بصورة
    final nextUp = (all.where((g) => g.q && !g.seen).toList()..sort((a, b) => a.a.compareTo(b.a))).firstOrNull
      ?? (all.where((g) => !g.seen && !g.isUpcoming && g.p.isNotEmpty && g.date.isNotEmpty).toList()..sort((a, b) => b.date.compareTo(a.date))).firstOrNull;
    final sel = ref.watch(_selProvider);
    final w = MediaQuery.sizeOf(context).width;

    Future<void> bulk(void Function(Map<String, dynamic>) fn, String msg) async {
      final groups = all.where((g) => sel.contains(g.key)).toList();
      final byP = <String, (Performer, Set<int>)>{};
      for (final g in groups) { for (final r in g.refs) { (byP[r.p.id] ??= (r.p, <int>{})).$2.add(r.idx); } }
      await ref.read(libraryProvider.notifier).upsertMany([for (final e in byP.values) e.$1.copyWith({'works': [for (var k = 0; k < e.$1.works.length; k++) () { final w = Map<String, dynamic>.from(e.$1.works[k]); if (e.$2.contains(k)) fn(w); return w; }()]})]);
      ref.read(_selProvider.notifier).clear();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg (${groups.length})')));
    }

    Widget stat(String v, String label, Color c) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: S.s2), decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rMd), border: Border.all(color: C.line)),
      child: Column(children: [Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)), Text(label, style: const TextStyle(color: C.muted, fontSize: 11.5))])));

    final tabsBar = SliverPersistentHeader(pinned: true, delegate: _Bar(52, Container(color: C.bg, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: 8), children: [
      for (final e in workTabs.entries) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(
        selected: st.tab == e.key, showCheckmark: false, avatar: Icon(e.value.$2, size: 18),
        label: Text('${e.value.$1}${(counts[e.key] ?? 0) > 0 ? ' ${counts[e.key]}' : ''}'),
        onSelected: (_) => n.set(st.copy(tab: e.key)))),
    ]))));

    final lists = ref.watch(wlistsProvider).value ?? const <NamedList>[];
    final tools = SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, 2, S.s4, S.s2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(workTabs[st.tab]!.$3, style: const TextStyle(color: C.muted, fontSize: 12.5))),
        if (st.tab.index <= WTab.top.index && st.tab != WTab.upcoming) PopupMenuButton<WSort>(tooltip: 'الترتيب', initialValue: st.sort, onSelected: (v) => n.set(st.copy(sort: v)), icon: const Icon(Icons.sort_rounded),
          itemBuilder: (_) => const [PopupMenuItem(value: WSort.date, child: Text('الأحدث صدورًا')), PopupMenuItem(value: WSort.rating, child: Text('تقييمي')), PopupMenuItem(value: WSort.title, child: Text('العنوان'))]),
        if (st.tab.index <= WTab.top.index) IconButton(tooltip: st.grid ? 'عرض قائمة' : 'عرض شبكة', onPressed: () => n.set(st.copy(grid: !st.grid)), icon: Icon(st.grid ? Icons.view_list_rounded : Icons.grid_view_rounded)),
      ]),
      if (lists.isNotEmpty || st.studio.isNotEmpty) SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        if (st.studio.isNotEmpty) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: InputChip(avatar: const Icon(Icons.business_rounded, size: 16), label: Text(st.studio), onDeleted: () => n.set(st.copy(studio: '')))),
        for (final wl in lists) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: FilterChip(avatar: const Icon(Icons.playlist_play_rounded, size: 18), label: Text(wl.name), selected: st.wl == wl.id, showCheckmark: false, onSelected: (v) => n.set(st.copy(wl: v ? wl.id : '')))),
      ])),
    ])));

    final Widget body;
    if (st.tab == WTab.performers) {
      body = _performers(context, l.toList());
    } else if (st.tab == WTab.studios) {
      body = _studios(l.toList(), (s) => n.set(st.copy(tab: WTab.recent, studio: s)));
    } else if (list.isEmpty) {
      body = SliverFillRemaining(hasScrollBody: false, child: EmptyState(
        title: switch (st.tab) { WTab.watch => 'قائمة المشاهدة فارغة', WTab.upcoming => 'لا إصدارات قادمة', WTab.diary => 'لا يوميات بعد', WTab.top => 'لا أعمال مقيّمة 4+', WTab.seen => 'لم تعلّمي شيئًا «شاهدته» بعد', _ => q.isNotEmpty ? 'لا نتائج' : 'لا أعمال هنا' },
        body: switch (st.tab) { WTab.watch => 'اضغطي على أي عمل ثم 🔖 «للمشاهدة» ليظهر هنا.', WTab.diary => 'كل عمل تعلّمينه «شاهدته» يُسجَّل هنا بتاريخه.', WTab.upcoming => 'الإصدارات القادمة تظهر هنا تلقائيًا عند تحديث أعمال ممثلاتك.', _ => q.isNotEmpty ? 'جرّبي كلمة أخرى.' : 'أضيفي أعمالًا من صفحة الممثلة أو حدّثيها من المصدر.' }));
    } else if (st.tab == WTab.diary) {
      body = SliverList.builder(itemCount: list.length, itemBuilder: (c, i) {
        final g = list[i]; final head = i == 0 || list[i - 1].wd.substring(0, 7) != g.wd.substring(0, 7);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (head) Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s1), child: Text('${_month(g.wd)} · ${list.where((x) => x.wd.startsWith(g.wd.substring(0, 7))).length}', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700))),
          _DiaryRow(g: g),
        ]);
      });
    } else if (st.grid) {
      body = SliverPadding(padding: const EdgeInsets.symmetric(horizontal: S.s4), sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: w < 600 ? 200 : 260, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3, childAspectRatio: .97),
        itemCount: list.length, itemBuilder: (c, i) => WorkPoster(g: list[i])));
    } else {
      final cols = w >= 1300 ? 4 : w >= 900 ? 3 : w >= 600 ? 2 : 1;
      body = SliverPadding(padding: const EdgeInsets.symmetric(horizontal: S.s4), sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 112, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3),
        itemCount: list.length, itemBuilder: (c, i) => WorkCard(g: list[i])));
    }

    return Scaffold(
      bottomNavigationBar: sel.isEmpty ? null : SafeArea(child: Container(margin: const EdgeInsets.fromLTRB(S.s3, 0, S.s3, 76), padding: const EdgeInsets.all(S.s2),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line2)),
        child: Row(children: [
          IconButton(tooltip: 'إلغاء التحديد', onPressed: () => ref.read(_selProvider.notifier).clear(), icon: const Icon(Icons.close_rounded)),
          Text('${sel.length} محدد'), const Spacer(),
          IconButton(tooltip: 'شاهدتها', onPressed: () => bulk((w) { w['w'] = 1; w['wd'] = todayStr(); w.remove('q'); }, 'عُلّمت مشاهدة'), icon: const Icon(Icons.check_circle_rounded, color: C.ok)),
          IconButton(tooltip: 'للمشاهدة', onPressed: () => bulk((w) { w['q'] = 1; }, 'أُضيفت لقائمة المشاهدة'), icon: const Icon(Icons.bookmark_add_rounded, color: C.gold)),
          IconButton(tooltip: 'إلغاء المشاهدة', onPressed: () => bulk((w) { w.remove('w'); w.remove('wd'); }, 'أُلغيت المشاهدة'), icon: const Icon(Icons.remove_done_rounded)),
        ]))),
      body: SafeArea(bottom: false, child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الأعمال', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: S.s3),
          Row(children: [
            stat('${all.length}', 'عمل', C.text), const SizedBox(width: 8),
            stat('${all.isEmpty ? 0 : (seen * 100 / all.length).round()}٪', 'شاهدتِ', C.ok), const SizedBox(width: 8),
            stat('$watchN', 'للمشاهدة', C.gold), const SizedBox(width: 8),
            stat('$upN', 'قادم', C.rose),
          ]),
          if (nextUp != null && q.isEmpty && sel.isEmpty) ...[const SizedBox(height: S.s4), _NextUp(g: nextUp)],
          const SizedBox(height: S.s3),
          SearchBar(
            hintText: 'ابحثي بالعنوان أو الاستوديو أو الممثلة…', leading: const Icon(Icons.search_rounded), onChanged: (v) => n.set(st.copy(q: v)),
            backgroundColor: const WidgetStatePropertyAll(C.surface), elevation: const WidgetStatePropertyAll(0), side: const WidgetStatePropertyAll(BorderSide(color: C.line2))),
          if (sel.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('اضغطي على عمل لتفاصيله · اضغطي مطوّلًا لتحديد عدة أعمال', style: TextStyle(color: C.muted, fontSize: 12))),
        ]))),
        tabsBar, tools, body,
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ])));
  }

  /// تقدّم كل ممثلة: شاهدتِ كم من أعمالها.
  static Widget _performers(BuildContext context, List<WorkGroup> l) {
    final by = <String, (Performer, int, int)>{};
    for (final g in l) { for (final p in g.who) { final e = by[p.id]; by[p.id] = (p, (e?.$2 ?? 0) + 1, (e?.$3 ?? 0) + (g.seen ? 1 : 0)); } }
    final rows = by.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    if (rows.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'لا أعمال بعد', body: 'أضيفي أعمالًا من صفحة الممثلة.'));
    return SliverList.builder(itemCount: rows.length, itemBuilder: (c, i) { final (p, total, seen) = rows[i];
      return InkWell(onTap: () => c.push('/p/${p.id}'), child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4, vertical: S.s2), child: Row(children: [
        SizedBox(width: 48, height: 48, child: ClipOval(child: Photo(p.cover, name: p.name, fallbacks: p.coverFallbacks))),
        const SizedBox(width: S.s3),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700))), Text('شاهدتِ $seen من $total', style: const TextStyle(color: C.muted, fontSize: 12.5))]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: total == 0 ? 0 : seen / total, minHeight: 6, backgroundColor: C.surface2, color: seen == total ? C.ok : C.gold)),
        ])),
      ])));
    });
  }

  static Widget _studios(List<WorkGroup> l, void Function(String) open) {
    final by = <String, (String, int, int, String)>{};
    for (final g in l) { if (g.s.trim().isEmpty) continue; final k = norm(g.s); final e = by[k]; by[k] = (e?.$1 ?? g.s, (e?.$2 ?? 0) + 1, (e?.$3 ?? 0) + (g.seen ? 1 : 0), (e?.$4 ?? '').isNotEmpty ? e!.$4 : g.p); }
    final rows = by.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    if (rows.isEmpty) return const SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'لا استوديوهات', body: 'أعمالك بلا اسم استوديو.'));
    return SliverPadding(padding: const EdgeInsets.symmetric(horizontal: S.s4), sliver: SliverGrid.builder(itemCount: rows.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3, childAspectRatio: 1.15),
      itemBuilder: (c, i) { final (name, total, seen, img) = rows[i];
        return Semantics(button: true, label: name, child: InkWell(borderRadius: BorderRadius.circular(S.rLg), onTap: () => open(name), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: SizedBox(width: double.infinity, child: Photo(img, name: name, alignment: Alignment.center)))),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$total عمل · شاهدتِ $seen', style: const TextStyle(color: C.muted, fontSize: 12)),
        ]))); }));
  }

  static String _month(String d) { const m = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر']; final mo = int.tryParse(d.length >= 7 ? d.substring(5, 7) : '') ?? 1; return '${m[mo - 1]} ${d.substring(0, 4)}'; }
}

class _Bar extends SliverPersistentHeaderDelegate {
  _Bar(this.h, this.child); final double h; final Widget child;
  @override double get minExtent => h;
  @override double get maxExtent => h;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override bool shouldRebuild(_Bar old) => true;
}

/// بطاقة «شاهدي التالي» الكبيرة.
class _NextUp extends ConsumerWidget {
  const _NextUp({required this.g});
  final WorkGroup g;
  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(onTap: () => showWorkSheet(context, ref, g.key), child: AspectRatio(aspectRatio: 16 / 8, child: ClipRRect(borderRadius: BorderRadius.circular(S.rXl), child: Stack(fit: StackFit.expand, children: [
    Photo(g.p, name: g.s.isNotEmpty ? g.s : g.t, alignment: Alignment.center),
    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xE60A0810)], stops: [.35, 1]))),
    Positioned(left: S.s3, right: S.s3, bottom: S.s3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(g.q ? '🔖 شاهدي التالي' : '▶ جديد لم تشاهديه', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 12.5)),
      Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
      Text([g.who.map((p) => p.name).take(2).join('، '), if (g.s.isNotEmpty) g.s].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
    ])),
  ]))));
}

/// بطاقة عمل للشبكة: صورة عريضة + حالة واضحة (شوهد/للمشاهدة/قادم/تقييم) + العنوان والممثلات.
class WorkPoster extends ConsumerWidget {
  const WorkPoster({super.key, required this.g});
  final WorkGroup g;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final du = g.daysUntil;
    if (g.p.isEmpty && (g.key.startsWith('is:') || g.key.startsWith('ip:'))) Future.microtask(() => ref.read(posterResolverProvider.notifier).want(g.key));   // صورة ناقصة ⇒ تُجلب بمعرّف المشهد
    final sel = ref.watch(_selProvider); final on = sel.contains(g.key);
    Widget badge(Widget child, Color bg) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)), child: child);
    return Semantics(button: true, label: g.t, child: GestureDetector(
      onTap: () => sel.isNotEmpty ? ref.read(_selProvider.notifier).toggle(g.key) : showWorkSheet(context, ref, g.key),
      onLongPress: () => ref.read(_selProvider.notifier).toggle(g.key),
      child: Container(decoration: BoxDecoration(color: on ? C.gold.withValues(alpha: .18) : C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: on ? C.gold : C.line)), clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 16 / 9, child: Stack(fit: StackFit.expand, children: [
            Photo(g.p, name: g.s.isNotEmpty ? g.s : g.t, alignment: Alignment.center),
            if (g.seen) Positioned(top: 6, right: 6, child: badge(const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_rounded, size: 13, color: Colors.white), SizedBox(width: 2), Text('شاهدته', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))]), C.ok))
            else if (g.q) Positioned(top: 6, right: 6, child: badge(const Icon(Icons.bookmark_rounded, size: 14, color: Color(0xFF1A1208)), C.gold)),
            if (g.isUpcoming && du != null && du >= 0) Positioned(bottom: 6, right: 6, child: badge(Text(du == 0 ? 'اليوم' : 'بعد $du يوم', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)), C.rose)),
            if (g.r > 0) Positioned(bottom: 6, left: 6, child: badge(Text('★ ${g.r}', style: const TextStyle(color: C.gold2, fontSize: 11, fontWeight: FontWeight.w700)), const Color(0xCC0A0810))),
            if (on) const Positioned(top: 6, left: 6, child: Icon(Icons.check_circle_rounded, color: C.gold, size: 22)),
          ])),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.25)),
            const Spacer(),
            Text(g.who.map((p) => p.name).take(2).join('، ') + (g.who.length > 2 ? ' +${g.who.length - 2}' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.gold, fontSize: 11.5)),
            Text([if (g.s.isNotEmpty) g.s, if (g.date.isNotEmpty) g.date.substring(0, g.d.isNotEmpty ? 10 : 4)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 11)),
          ]))),
        ]))));
  }
}

class WorkCard extends ConsumerWidget {
  const WorkCard({super.key, required this.g});
  final WorkGroup g;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final du = g.daysUntil;
    if (g.p.isEmpty && (g.key.startsWith('is:') || g.key.startsWith('ip:'))) Future.microtask(() => ref.read(posterResolverProvider.notifier).want(g.key));   // صورة ناقصة ⇒ تُجلب بمعرّف المشهد
    final sel = ref.watch(_selProvider); final on = sel.contains(g.key);
    return Material(color: on ? C.gold.withValues(alpha: .18) : C.surface, borderRadius: BorderRadius.circular(S.rLg), clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => sel.isNotEmpty ? ref.read(_selProvider.notifier).toggle(g.key) : showWorkSheet(context, ref, g.key),
      onLongPress: () => ref.read(_selProvider.notifier).toggle(g.key),
      child: Row(children: [
        SizedBox(width: 150, height: double.infinity, child: Stack(fit: StackFit.expand, children: [
          Photo(g.p, name: g.s.isNotEmpty ? g.s : g.t, alignment: Alignment.center),
          if (g.seen) const Positioned(top: 6, right: 6, child: Icon(Icons.check_circle_rounded, color: C.ok, size: 22)),
          if (g.isUpcoming && du != null && du >= 0) Positioned(bottom: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.rose, borderRadius: BorderRadius.circular(99)), child: Text(du == 0 ? 'اليوم' : 'بعد $du يوم', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)))),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.all(S.s3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text([if (g.s.isNotEmpty) g.s, if (g.date.isNotEmpty) g.date.substring(0, g.d.isNotEmpty ? 10 : 4)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5)),
          Text(g.who.map((p) => p.name).take(2).join('، ') + (g.who.length > 2 ? ' +${g.who.length - 2}' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.gold, fontSize: 12)),
          const Spacer(),
          Row(children: [if (g.r > 0) Stars(g.r.toDouble(), size: 13), const Spacer(), if (g.q && !g.seen) const Icon(Icons.bookmark_rounded, color: C.gold, size: 18)]),
        ]))),
      ]),
    ));
  }
}

class _DiaryRow extends ConsumerWidget {
  const _DiaryRow({required this.g});
  final WorkGroup g;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    onTap: () => showWorkSheet(context, ref, g.key),
    leading: Container(width: 46, alignment: Alignment.center, child: Text(g.wd.substring(8, 10), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.gold2))),
    title: Text(g.t, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(g.who.map((p) => p.name).join('، '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
    trailing: g.r > 0 ? Stars(g.r.toDouble(), size: 13) : null,
  );
}

/// ورقة العمل: الحالة (شاهدته/للمشاهدة)، التقييم، الملاحظة، الممثلات، الرابط. التعديل يُطبَّق على كل نسخ العمل.
Future<void> showWorkSheet(BuildContext context, WidgetRef ref, String key) => showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _WorkSheet(k: key));

class _WorkSheet extends ConsumerStatefulWidget {
  const _WorkSheet({required this.k});
  final String k;
  @override ConsumerState<_WorkSheet> createState() => _WorkSheetState();
}

class _WorkSheetState extends ConsumerState<_WorkSheet> {
  late final _note = TextEditingController();
  bool _init = false;
  @override void dispose() { _note.dispose(); super.dispose(); }

  Future<void> _apply(WorkGroup g, void Function(Map<String, dynamic>) fn) => ref.read(libraryProvider.notifier).upsertMany(applyToGroup(g, fn));

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(worksProvider).where((x) => x.key == widget.k).firstOrNull;
    if (g == null) return const SizedBox(height: 200, child: Center(child: Text('العمل غير موجود')));
    if (!_init) { _init = true; _note.text = g.n; }
    return SingleChildScrollView(padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s5 + MediaQuery.viewInsetsOf(context).bottom), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (g.p.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(S.rLg), child: AspectRatio(aspectRatio: 16 / 9, child: Photo(g.p, name: g.t))),
      const SizedBox(height: S.s3),
      Text(g.t, style: Theme.of(context).textTheme.titleLarge),
      Text([if (g.s.isNotEmpty) g.s, if (g.date.isNotEmpty) g.d.isNotEmpty ? g.d : g.y, if (g.du > 0) '${g.du} د'].join(' · '), style: const TextStyle(color: C.muted)),
      if (g.ds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s2), child: Text(g.ds, style: const TextStyle(height: 1.6))),
      const SizedBox(height: S.s4),
      Row(children: [
        Expanded(child: FilledButton.icon(
          onPressed: () => _apply(g, (w) { if (g.seen) { w.remove('w'); w.remove('wd'); } else { w['w'] = 1; w['wd'] = todayStr(); w.remove('q'); } }),
          icon: Icon(g.seen ? Icons.undo_rounded : Icons.check_rounded), label: Text(g.seen ? 'لم أشاهده' : 'شاهدته اليوم'),
          style: g.seen ? FilledButton.styleFrom(backgroundColor: C.surface2, foregroundColor: C.text) : null)),
        const SizedBox(width: S.s2),
        Expanded(child: OutlinedButton.icon(onPressed: () => _apply(g, (w) { if (g.q) { w.remove('q'); } else { w['q'] = 1; } }),
          icon: Icon(g.q ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: C.gold), label: Text(g.q ? 'في قائمة المشاهدة' : 'للمشاهدة'))),
      ]),
      const SizedBox(height: S.s4),
      Row(children: [
        const Text('تقييمي'), const SizedBox(width: S.s3),
        for (var i = 1; i <= 5; i++) IconButton(visualDensity: VisualDensity.compact, tooltip: '$i', onPressed: () => _apply(g, (w) { if (g.r == i) { w.remove('r'); } else { w['r'] = i; } }),
          icon: Icon(g.r >= i ? Icons.star_rounded : Icons.star_outline_rounded, color: C.gold)),
      ]),
      const SizedBox(height: S.s2),
      TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظة / لحظة مفضلة', hintText: 'مثال: 12:30 أفضل مشهد'),
        onSubmitted: (v) => _apply(g, (w) { if (v.trim().isEmpty) { w.remove('n'); } else { w['n'] = v.trim(); } })),
      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () { _apply(g, (w) { final v = _note.text.trim(); if (v.isEmpty) { w.remove('n'); } else { w['n'] = v; } }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظت الملاحظة'))); }, child: const Text('حفظ الملاحظة'))),
      const SizedBox(height: S.s2),
      const Text('قوائم الأعمال', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)),
      Wrap(spacing: S.s2, children: [
        for (final wl in ref.watch(wlistsProvider).value ?? const <NamedList>[]) FilterChip(label: Text(wl.name), selected: g.ls.contains(wl.id), onSelected: (v) => _apply(g, (w) { final ls = {...((w['ls'] as List?) ?? const []).cast<String>()}; if (v) { ls.add(wl.id); } else { ls.remove(wl.id); } if (ls.isEmpty) { w.remove('ls'); } else { w['ls'] = ls.toList(); } })),
        ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('قائمة جديدة'), onPressed: () async {
          final name = await askName(context, 'قائمة أعمال جديدة'); if (name == null || name.trim().isEmpty) return;
          final wl = await ref.read(wlistsProvider.notifier).add(name);
          await _apply(g, (w) { final ls = {...((w['ls'] as List?) ?? const []).cast<String>(), wl.id}; w['ls'] = ls.toList(); });
        }),
      ]),
      const SizedBox(height: S.s3),
      const Text('الممثلات', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.s2),
      Wrap(spacing: S.s2, runSpacing: S.s2, children: [for (final p in g.who) ActionChip(
        avatar: CircleAvatar(backgroundColor: C.surface2, child: ClipOval(child: SizedBox.expand(child: Photo(p.cover, name: p.name, cacheWidth: 96)))),
        label: Text(p.name), onPressed: () { Navigator.pop(context); context.push('/p/${p.id}'); })]),
      if (g.u.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s3), child: SelectableText(g.u, style: const TextStyle(color: C.muted, fontSize: 12))),
      const SizedBox(height: S.s3),
      Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف العمل؟'), content: Text('يُزال «${g.t}» من ${g.who.length == 1 ? 'صفحة ${g.who.first.name}' : '${g.who.length} ممثلات'}.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: Colors.white), onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
        if (ok != true) return;
        final byP = <String, Set<int>>{}; for (final r in g.refs) { (byP[r.p.id] ??= {}).add(r.idx); }
        await ref.read(libraryProvider.notifier).upsertMany([for (final r in g.refs.map((x) => x.p).toSet()) r.copyWith({'works': [for (var k = 0; k < r.works.length; k++) if (!byP[r.id]!.contains(k)) r.works[k]]})]);
        if (context.mounted) Navigator.pop(context);
      }, icon: const Icon(Icons.delete_outline_rounded, color: C.danger), label: const Text('حذف العمل', style: TextStyle(color: C.danger)))),
    ]));
  }
}
