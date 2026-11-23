import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/journal.dart';
import '../../../domain/performer.dart';
import '../../../domain/works.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart' show worksProvider;

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// «يومياتي»: ملخص الشهر، الأهداف والمراحل، وتقويم المشاهدة.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key, this.tab = 0});
  final int tab;
  @override ConsumerState<JournalScreen> createState() => _JournalState();
}

class _JournalState extends ConsumerState<JournalScreen> {
  late DateTime _m = DateTime(DateTime.now().year, DateTime.now().month);
  int _goal = 0;

  @override
  void initState() {
    super.initState();
    () async { final g = await (await ref.read(repoProvider.future)).kvGet('watch_goal'); if (mounted) setState(() => _goal = (g as num?)?.toInt() ?? 0); }();
  }

  Future<void> _setGoal() async {
    final c = TextEditingController(text: _goal > 0 ? '$_goal' : '');
    final v = await showDialog<int>(context: context, builder: (d) => AlertDialog(title: const Text('هدف الشهر'), content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(hintText: 'كم عملًا تريد أن تشاهد كل شهر؟ (0 = بلا هدف)')),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim()) ?? 0), child: const Text('حفظ'))]));
    if (v == null) return;
    await (await ref.read(repoProvider.future)).kvSet('watch_goal', v.clamp(0, 999));
    setState(() => _goal = v.clamp(0, 999));
  }

  @override
  Widget build(BuildContext context) {
    final works = ref.watch(worksProvider);
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    return DefaultTabController(length: 3, initialIndex: widget.tab, child: Scaffold(
      appBar: AppBar(title: const Text('يومياتي'), bottom: const TabBar(tabs: [Tab(text: 'ملخص الشهر'), Tab(text: 'الأهداف'), Tab(text: 'التقويم')])),
      body: TabBarView(children: [_month(works, lib), _goals(works, lib), _calendar(works)]),
    ));
  }

  // ===== ملخص الشهر =====
  Widget _month(List<WorkGroup> works, List<Performer> lib) {
    final r = monthReview(works, lib, _m.year, _m.month);
    final now = DateTime.now(); final isCur = _m.year == now.year && _m.month == now.month;
    return ListView(padding: const EdgeInsets.all(S.s4), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _m = DateTime(_m.year, _m.month - 1)), icon: const Icon(Icons.chevron_right_rounded)),
        Expanded(child: Text('${_months[_m.month - 1]} ${_m.year}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        IconButton(onPressed: isCur ? null : () => setState(() => _m = DateTime(_m.year, _m.month + 1)), icon: const Icon(Icons.chevron_left_rounded)),
      ]),
      const SizedBox(height: S.s3),
      Wrap(spacing: S.s2, runSpacing: S.s2, children: [
        _stat('${r.watched}', 'شاهدت', sub: r.prevWatched == 0 && r.watched == 0 ? null : r.delta == 0 ? 'مثل الشهر السابق' : r.delta > 0 ? '▲ ${r.delta} عن السابق' : '▼ ${-r.delta} عن السابق', subColor: r.delta >= 0 ? C.ok : C.rose),
        _stat('${r.activeDays}', 'يوم مشاهدة'),
        _stat('${r.added}', 'ممثلة أضفتها'),
        _stat(r.rated == 0 ? '—' : r.avgRating.toStringAsFixed(1), 'متوسط تقييمك'),
      ]),
      if (_goal > 0 && isCur) ...[const SizedBox(height: S.s3), _goalBar(r.watched)],
      if (r.watched == 0) const Padding(padding: EdgeInsets.only(top: S.s5), child: Center(child: Text('لا مشاهدات مسجلة في هذا الشهر', style: TextStyle(color: C.muted)))),
      if (r.topPerformers.isNotEmpty) ...[
        _h('الأكثر مشاهدة'),
        for (final (p, n) in r.topPerformers) ListTile(contentPadding: EdgeInsets.zero, onTap: () => context.push('/p/${p.id}'),
          leading: _avatar(p), title: Text(p.name), trailing: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, color: C.gold))),
      ],
      if (r.firstTime.isNotEmpty) ...[_h('اكتشافات الشهر (أول مرة)'), Wrap(spacing: 8, runSpacing: 8, children: [for (final p in r.firstTime) ActionChip(avatar: _avatar(p, 12), label: Text(p.name), onPressed: () => context.push('/p/${p.id}'))])],
      if (r.topStudios.isNotEmpty) ...[_h('الاستوديوهات'), for (final (s, n) in r.topStudios) _bar(s, n, r.topStudios.first.$2)],
      if (r.topTags.isNotEmpty) ...[_h('الطابع الغالب'), Wrap(spacing: 8, runSpacing: 8, children: [for (final (t, n) in r.topTags) Chip(label: Text('$t · $n'))])],
      if (r.bestDayCount > 1) ...[_h('أنشط يوم'), Text('${r.bestDay} — ${r.bestDayCount} أعمال', style: const TextStyle(color: C.muted))],
    ]);
  }

  // ===== الأهداف والمراحل =====
  Widget _goals(List<WorkGroup> works, List<Performer> lib) {
    final total = works.where((g) => g.seen).length;
    final (next, prev) = nextMilestone(total);
    final cur = monthReview(works, lib, DateTime.now().year, DateTime.now().month).watched;
    final ms = performerMilestones(works, lib);
    final st = streaks(works.where((g) => g.seen).map((g) => g.wd));
    return ListView(padding: const EdgeInsets.all(S.s4), children: [
      Card(child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('هدف الشهر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), TextButton(onPressed: _setGoal, child: Text(_goal > 0 ? 'تغيير' : 'حدّد هدفًا'))]),
        if (_goal > 0) _goalBar(cur) else const Text('حدّد عدد الأعمال التي تريد مشاهدتها كل شهر، ويُتابع تقدمك هنا وفي ملخص الشهر.', style: TextStyle(color: C.muted)),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('المرحلة التالية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        Text('شاهدت $total عملًا — باقي ${next - total} على $next', style: const TextStyle(color: C.muted)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (total - prev) / (next - prev), minHeight: 8, borderRadius: BorderRadius.circular(9)),
        const SizedBox(height: 10),
        Text('🔥 سلسلتك الحالية: ${st.$2} يوم · الأطول: ${st.$1} يوم', style: const TextStyle(color: C.gold2)),
      ]))),
      _h('إكمال أعمال مفضلاتك'),
      if (ms.isEmpty) const Text('تظهر هنا مفضلاتك اللاتي لهن 5 أعمال فأكثر.', style: TextStyle(color: C.muted)),
      for (final m in ms.take(40)) ListTile(contentPadding: EdgeInsets.zero, onTap: () => context.push('/p/${m.p.id}'), leading: _avatar(m.p),
        title: Text(m.p.name), subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: m.seen / m.total, minHeight: 5, borderRadius: BorderRadius.circular(9))),
        trailing: Text(m.seen == m.total ? '✓ ${m.total}' : '${m.seen}/${m.total}', style: TextStyle(fontWeight: FontWeight.w700, color: m.seen == m.total ? C.ok : null))),
    ]);
  }

  // ===== تقويم المشاهدة (مثل GitHub) =====
  Widget _calendar(List<WorkGroup> works) {
    const weeks = 26;
    final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
    final hm = watchHeatmap(works, days: weeks * 7);
    final maxV = hm.values.fold<int>(1, (a, b) => b > a ? b : a);
    final end = today.add(Duration(days: 6 - (today.weekday % 7)));   // آخر سبت
    final start = end.subtract(const Duration(days: weeks * 7 - 1));
    final total = hm.values.fold<int>(0, (a, b) => a + b);
    Color cell(int v) => v == 0 ? C.surface : Color.lerp(C.gold.withValues(alpha: .3), C.gold, (v / maxV).clamp(0, 1).toDouble())!;
    return ListView(padding: const EdgeInsets.all(S.s4), children: [
      Text('$total عملًا في آخر ستة أشهر · ${hm.length} يوم مشاهدة', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: S.s3),
      SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var w = 0; w < weeks; w++) Column(children: [
          for (var d = 0; d < 7; d++) () {
            final day = start.add(Duration(days: w * 7 + d));
            final k = day.toIso8601String().substring(0, 10); final v = hm[k] ?? 0;
            return Tooltip(message: '$k: $v', child: Container(width: 14, height: 14, margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(color: day.isAfter(today) ? Colors.transparent : cell(v), borderRadius: BorderRadius.circular(3))));
          }(),
        ]),
      ])),
      const SizedBox(height: S.s2),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Text('أقل ', style: TextStyle(color: C.muted, fontSize: 11)),
        for (final v in [0, 1, (maxV / 2).ceil(), maxV]) Container(width: 12, height: 12, margin: const EdgeInsets.all(1.5), decoration: BoxDecoration(color: cell(v), borderRadius: BorderRadius.circular(3))),
        const Text(' أكثر', style: TextStyle(color: C.muted, fontSize: 11))]),
    ]);
  }

  Widget _goalBar(int cur) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(cur >= _goal ? '🎯 حققت هدف الشهر ($cur/$_goal)' : 'هدف الشهر: $cur من $_goal', style: TextStyle(fontWeight: FontWeight.w700, color: cur >= _goal ? C.ok : null)),
    const SizedBox(height: 6),
    LinearProgressIndicator(value: (cur / _goal).clamp(0.0, 1.0), minHeight: 8, borderRadius: BorderRadius.circular(9)),
  ]);

  Widget _stat(String v, String l, {String? sub, Color? subColor}) => Container(width: 160, padding: const EdgeInsets.all(S.s3),
    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(S.rLg), border: Border.all(color: C.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.gold)), Text(l, style: const TextStyle(color: C.muted)),
      if (sub != null) Text(sub, style: TextStyle(color: subColor, fontSize: 12)),
    ]));
  Widget _h(String t) => Padding(padding: const EdgeInsets.only(top: S.s4, bottom: S.s2), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)));
  Widget _bar(String l, int n, int max) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
    SizedBox(width: 120, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
    Expanded(child: LinearProgressIndicator(value: n / max, minHeight: 8, borderRadius: BorderRadius.circular(9))), const SizedBox(width: 8), Text('$n'),
  ]));
  Widget _avatar(Performer p, [double r = 18]) => CircleAvatar(radius: r, backgroundColor: C.surface, child: p.photos.isEmpty ? Text(p.name.isEmpty ? '?' : p.name.characters.first, style: TextStyle(fontSize: r * .8))
    : ClipOval(child: SizedBox(width: r * 2, height: r * 2, child: Photo(p.photos.first, name: p.name, cacheWidth: (r * 6).round()))));
}
