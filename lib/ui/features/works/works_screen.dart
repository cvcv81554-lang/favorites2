import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/sanitize.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final worksProvider = Provider<List<WorkGroup>>((ref) => groupWorks(ref.watch(libraryProvider).value ?? const []));

enum WTab { recent, watch, upcoming, seen, top, diary }

class _WState { final WTab tab; final String q; const _WState(this.tab, this.q); }
class _WN extends Notifier<_WState> { @override _WState build() => const _WState(WTab.recent, ''); void set(_WState s) => state = s; }
final _wProvider = NotifierProvider<_WN, _WState>(_WN.new);

/// مركز الأعمال: الأحدث، للمشاهدة، القادمة، شاهدتها، الأعلى تقييمًا، يوميات المشاهدة.
class WorksScreen extends ConsumerWidget {
  const WorksScreen({super.key});

  static const tabs = {WTab.recent: 'الأحدث', WTab.watch: 'للمشاهدة', WTab.upcoming: 'القادمة', WTab.seen: 'شاهدتها', WTab.top: 'الأعلى تقييمًا', WTab.diary: 'يومياتي'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(worksProvider);
    final st = ref.watch(_wProvider);
    final n = ref.read(_wProvider.notifier);
    final t0 = todayStr();
    final q = norm(st.q);
    Iterable<WorkGroup> l = all;
    if (q.isNotEmpty) l = l.where((g) => norm('${g.t} ${g.s} ${g.who.map((p) => p.name).join(' ')}').contains(q));
    final list = switch (st.tab) {
      WTab.recent => (l.where((g) => !g.isUpcoming && g.date.isNotEmpty && g.date.compareTo(t0) <= 0).toList()..sort((a, b) => b.date.compareTo(a.date))),
      WTab.watch => (l.where((g) => g.q && !g.seen).toList()..sort((a, b) => b.a.compareTo(a.a))),
      WTab.upcoming => (l.where((g) => g.isUpcoming).toList()..sort((a, b) => a.date.compareTo(b.date))),
      WTab.seen => (l.where((g) => g.seen).toList()..sort((a, b) => b.wd.compareTo(a.wd))),
      WTab.top => (l.where((g) => g.r >= 4).toList()..sort((a, b) => b.r.compareTo(a.r))),
      WTab.diary => (l.where((g) => g.seen && g.wd.isNotEmpty).toList()..sort((a, b) => b.wd.compareTo(a.wd))),
    };
    final seen = all.where((g) => g.seen).length;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1300 ? 4 : w >= 900 ? 3 : w >= 600 ? 2 : 1;
    return Scaffold(body: SafeArea(bottom: false, child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('الأعمال', style: Theme.of(context).textTheme.headlineSmall),
        Text('${all.length} عمل · شاهدتِ ${all.isEmpty ? 0 : (seen * 100 / all.length).round()}٪ · ${all.where((g) => g.q && !g.seen).length} للمشاهدة · ${all.where((g) => g.isUpcoming).length} قادم', style: const TextStyle(color: C.muted)),
      ]))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(S.s4), child: SearchBar(
        hintText: 'ابحث بالعنوان أو الاستوديو أو الممثلة…', leading: const Icon(Icons.search_rounded), onChanged: (v) => n.set(_WState(st.tab, v)),
        backgroundColor: const WidgetStatePropertyAll(C.surface), elevation: const WidgetStatePropertyAll(0), side: const WidgetStatePropertyAll(BorderSide(color: C.line2)),
      ))),
      SliverToBoxAdapter(child: SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.s4), children: [
        for (final e in tabs.entries) Padding(padding: const EdgeInsetsDirectional.only(end: S.s2), child: ChoiceChip(label: Text(e.value), selected: st.tab == e.key, showCheckmark: false, onSelected: (_) => n.set(_WState(e.key, st.q)))),
      ]))),
      if (list.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: switch (st.tab) { WTab.watch => 'قائمة المشاهدة فارغة', WTab.upcoming => 'لا إصدارات قادمة', WTab.diary => 'لا يوميات بعد', _ => 'لا أعمال هنا' },
          body: switch (st.tab) { WTab.watch => 'اضغط 🔖 على أي عمل لتضيفه هنا.', WTab.diary => 'كل عمل تعلّمه «شاهدته» يُسجَّل هنا بتاريخه.', _ => 'أضف أعمالًا من صفحة الممثلة أو استورد نسختك.' }))
      else if (st.tab == WTab.diary)
        SliverList.builder(itemCount: list.length, itemBuilder: (c, i) {
          final g = list[i]; final head = i == 0 || list[i - 1].wd.substring(0, 7) != g.wd.substring(0, 7);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (head) Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s1), child: Text(_month(g.wd), style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700))),
            _DiaryRow(g: g),
          ]);
        })
      else
        SliverPadding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 140), sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 112, mainAxisSpacing: S.s3, crossAxisSpacing: S.s3),
          itemCount: list.length, itemBuilder: (c, i) => WorkCard(g: list[i]),
        )),
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ])));
  }

  static String _month(String d) { const m = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر']; final mo = int.tryParse(d.length >= 7 ? d.substring(5, 7) : '') ?? 1; return '${m[mo - 1]} ${d.substring(0, 4)}'; }
}

class WorkCard extends ConsumerWidget {
  const WorkCard({super.key, required this.g});
  final WorkGroup g;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final du = g.daysUntil;
    return Material(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), clipBehavior: Clip.antiAlias, child: InkWell(
      onTap: () => showWorkSheet(context, ref, g.key),
      child: Row(children: [
        SizedBox(width: 150, height: double.infinity, child: Stack(fit: StackFit.expand, children: [
          Photo(g.p, name: g.s.isNotEmpty ? g.s : g.t, cacheWidth: 400),
          if (g.seen) const Positioned(top: 6, right: 6, child: Icon(Icons.check_circle_rounded, color: C.ok, size: 22)),
          if (g.isUpcoming && du != null && du >= 0) Positioned(bottom: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.rose, borderRadius: BorderRadius.circular(99)), child: Text(du == 0 ? 'اليوم' : 'بعد $du يوم', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)))),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.all(S.s3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(g.t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text([g.who.map((p) => p.name).take(2).join('، '), if (g.s.isNotEmpty) g.s, if (g.date.isNotEmpty) g.date.substring(0, g.d.isNotEmpty ? 10 : 4)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12.5)),
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
