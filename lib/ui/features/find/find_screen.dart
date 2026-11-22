import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/age_gate.dart';
import '../../../domain/performer.dart';
import '../../../domain/sanitize.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart';

/// البحث الشامل: صندوق واحد يبحث في الممثلات والأعمال والاستوديوهات والوسوم معًا، مع فلاتر للممثلات (العمر، البلد، التقييم، المفضلة).
/// محلي بالكامل — يبحث في مكتبتك على جهازك.
class FindScreen extends ConsumerStatefulWidget {
  const FindScreen({super.key});
  @override ConsumerState<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends ConsumerState<FindScreen> {
  final _q = TextEditingController();
  String q = '', tag = '', country = '';
  RangeValues age = const RangeValues(18, 60);
  double minRating = 0; bool favOnly = false, showFilters = false;
  final _open = <String>{};   // الأقسام المفتوحة كاملة

  @override void dispose() { _q.dispose(); super.dispose(); }

  bool get _filtering => age.start > 18 || age.end < 60 || country.isNotEmpty || minRating > 0 || favOnly;

  @override
  Widget build(BuildContext context) {
    final lib = (ref.watch(libraryProvider).value ?? const <Performer>[]).where((p) => !p.isMinor).toList();
    final works = ref.watch(worksProvider);
    final nq = norm(q), nt = norm(tag);
    bool hit(String s) => nq.isEmpty || norm(s).contains(nq);

    // الممثلات
    final perf = lib.where((p) {
      if (nt.isNotEmpty && !p.tags.any((t) => norm(t) == nt)) return false;
      if (nq.isNotEmpty && !(hit(p.name) || hit(p.aliases) || hit(p.country) || p.tags.any(hit) || hit(p.notes))) return false;
      final a = sdAge(p.birth).age;
      if ((age.start > 18 || age.end < 60) && (a == null || a < age.start || a > age.end)) return false;
      if (country.isNotEmpty && p.country.toUpperCase() != country) return false;
      if (minRating > 0 && p.rating < minRating) return false;
      if (favOnly && !p.fav) return false;
      return true;
    }).toList()..sort((a, b) => (norm(a.name).startsWith(nq) ? 0 : 1).compareTo(norm(b.name).startsWith(nq) ? 0 : 1));
    final active = nq.isNotEmpty || nt.isNotEmpty;
    // الأعمال
    final ws = !active ? <WorkGroup>[] : works.where((g) =>
      (nt.isEmpty || g.tg.any((t) => norm(t) == nt)) &&
      (nq.isEmpty || hit(g.t) || hit(g.s) || g.tg.any(hit) || g.who.any((p) => hit(p.name)))).toList()..sort((a, b) => b.date.compareTo(a.date));
    // الاستوديوهات
    final studios = <String, (String, int)>{};
    if (nq.isNotEmpty) { for (final g in works) { if (g.s.trim().isNotEmpty && hit(g.s)) { final k = norm(g.s); studios[k] = (studios[k]?.$1 ?? g.s.trim(), (studios[k]?.$2 ?? 0) + 1); } } }
    final st = studios.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    // الوسوم (من الممثلات والأعمال)
    final tags = <String, (String, int)>{};
    if (nq.isNotEmpty) {
      void add(String t) { if (t.trim().isEmpty || !hit(t)) return; final k = norm(t); tags[k] = (tags[k]?.$1 ?? t.trim(), (tags[k]?.$2 ?? 0) + 1); }
      for (final p in lib) { p.tags.forEach(add); }
      for (final g in works) { g.tg.forEach(add); }
    }
    final tg = tags.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
    final countries = {for (final p in lib) if (p.country.trim().length >= 2) p.country.trim().toUpperCase()}.toList()..sort();

    List<T> cut<T>(String k, List<T> l, int n) => _open.contains(k) ? l : l.take(n).toList();
    Widget head(String k, String title, int n, int shown) => Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s4, S.s1), child: Row(children: [
      Text('$title ($n)', style: const TextStyle(color: C.gold2, fontWeight: FontWeight.w700, fontSize: 15)), const Spacer(),
      if (n > shown || _open.contains(k)) TextButton(onPressed: () => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k)), child: Text(_open.contains(k) ? 'أقل' : 'عرض الكل')),
    ]));

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: TextField(controller: _q, autofocus: true, textInputAction: TextInputAction.search,
        decoration: const InputDecoration(hintText: 'ابحث عن ممثلة، عمل، استوديو، أو وسم…', border: InputBorder.none),
        onChanged: (v) => setState(() { q = v; tag = ''; })),
        actions: [
          if (q.isNotEmpty || tag.isNotEmpty) IconButton(tooltip: 'مسح', onPressed: () => setState(() { _q.clear(); q = ''; tag = ''; }), icon: const Icon(Icons.close_rounded)),
          IconButton(tooltip: 'الفلاتر', onPressed: () => setState(() => showFilters = !showFilters), icon: Badge(isLabelVisible: _filtering, child: const Icon(Icons.tune_rounded))),
        ]),
      body: CustomScrollView(slivers: [
        if (showFilters) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, 0), child: Container(padding: const EdgeInsets.all(S.s3),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('العمر: ${age.start.round()}–${age.end.round()}${age.end >= 60 ? '+' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            RangeSlider(values: age, min: 18, max: 60, divisions: 42, labels: RangeLabels('${age.start.round()}', '${age.end.round()}'), onChanged: (v) => setState(() => age = v)),
            const Text('التقييم', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 6, children: [for (final r in const [0.0, 3.0, 4.0, 5.0]) ChoiceChip(label: Text(r == 0 ? 'الكل' : '$r+'.replaceAll('.0', '')), selected: minRating == r, onSelected: (_) => setState(() => minRating = r))]),
            const SizedBox(height: 6),
            Row(children: [
              const Text('البلد', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(width: S.s3),
              DropdownButton<String>(value: country, items: [const DropdownMenuItem(value: '', child: Text('الكل')), for (final c in countries) DropdownMenuItem(value: c, child: Text(c))], onChanged: (v) => setState(() => country = v ?? '')),
              const Spacer(),
              FilterChip(label: const Text('المفضلة فقط'), selected: favOnly, onSelected: (v) => setState(() => favOnly = v)),
            ]),
            if (_filtering) Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => setState(() { age = const RangeValues(18, 60); country = ''; minRating = 0; favOnly = false; }), child: const Text('إلغاء الفلاتر'))),
          ])))),
        if (tag.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(S.s4, S.s3, S.s4, 0), child: Align(alignment: AlignmentDirectional.centerStart,
          child: InputChip(avatar: const Icon(Icons.sell_rounded, size: 16), label: Text('الوسم: $tag'), onDeleted: () => setState(() => tag = ''))))),
        if (!active && !_filtering) const SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'بحث في كل مكتبتك',
          body: 'اكتب اسم ممثلة أو عنوان عمل أو استوديو أو وسم — تظهر النتائج من كل الأقسام معًا.\nاضغط ⚙︎ لفلترة الممثلات بالعمر والبلد والتقييم.'))
        else ...[
          if (perf.isNotEmpty) ...[
            SliverToBoxAdapter(child: head('p', 'الممثلات', perf.length, 8)),
            SliverList.builder(itemCount: cut('p', perf, 8).length, itemBuilder: (c, i) { final p = perf[i]; final a = sdAge(p.birth).age;
              return ListTile(onTap: () => context.push('/p/${p.id}'),
                leading: SizedBox(width: 48, height: 48, child: ClipOval(child: Photo(p.cover, name: p.name, fallbacks: p.coverFallbacks))),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([if (a != null) '$a سنة', if (p.country.isNotEmpty) p.country, '${p.works.length} عمل', if (p.fav) '♥'].join(' · '), style: const TextStyle(color: C.muted)),
                trailing: p.rating > 0 ? Stars(p.rating, size: 13) : null); }),
          ],
          if (ws.isNotEmpty) ...[
            SliverToBoxAdapter(child: head('w', 'الأعمال', ws.length, 6)),
            SliverList.builder(itemCount: cut('w', ws, 6).length, itemBuilder: (c, i) { final g = ws[i];
              return ListTile(onTap: () => showWorkSheet(context, ref, g.key),
                leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 88, height: 52, child: WorkImage(g.p, name: g.s.isNotEmpty ? g.s : g.t))),
                title: Text(g.t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([g.who.map((p) => p.name).take(2).join('، '), if (g.s.isNotEmpty) g.s, if (g.date.isNotEmpty) g.date.substring(0, 4)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
                trailing: g.seen ? const Icon(Icons.check_circle_rounded, color: C.ok, size: 18) : null); }),
          ],
          if (st.isNotEmpty) ...[
            SliverToBoxAdapter(child: head('s', 'الاستوديوهات', st.length, 6)),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4), child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in cut('s', st, 6)) ActionChip(avatar: const Icon(Icons.business_rounded, size: 16), label: Text('${s.$1} · ${s.$2}'), onPressed: () => showStudioWorks(context, ref, s.$1)),
            ]))),
          ],
          if (tg.isNotEmpty) ...[
            SliverToBoxAdapter(child: head('t', 'الوسوم', tg.length, 10)),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s4), child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in cut('t', tg, 10)) ActionChip(avatar: const Icon(Icons.sell_rounded, size: 16), label: Text('${t.$1} · ${t.$2}'), onPressed: () => setState(() { tag = t.$1; _q.clear(); q = ''; })),
            ]))),
          ],
          if (perf.isEmpty && ws.isEmpty && st.isEmpty && tg.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'لا نتائج', body: 'جرّب كلمة أخرى أو خفّف الفلاتر.')),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ]),
    );
  }
}
