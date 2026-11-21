import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/performer.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../works/works_screen.dart';

/// الإحصائيات + ملخّص السنة (على الجهاز، مجانًا، بلا خوادم).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider).value ?? const <Performer>[];
    final works = ref.watch(worksProvider);
    final y = '$_year';
    final seenYear = works.where((g) => g.seen && g.wd.startsWith(y)).toList();
    final years = {for (final g in works) if (g.wd.length >= 4) int.tryParse(g.wd.substring(0, 4))}..remove(null);
    years.add(DateTime.now().year);
    // أكثر الممثلات مشاهدة هذه السنة
    final byP = <String, int>{}; for (final g in seenYear) { for (final p in g.who) { byP[p.id] = (byP[p.id] ?? 0) + 1; } }
    final topP = (byP.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => (lib.firstWhere((p) => p.id == e.key, orElse: () => Performer({'id': e.key, 'name': '—'})), e.value)).toList();
    final bySt = <String, int>{}; for (final g in seenYear) { if (g.s.isNotEmpty) bySt[g.s] = (bySt[g.s] ?? 0) + 1; }
    final topSt = (bySt.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
    final byMonth = List<int>.filled(12, 0); for (final g in seenYear) { final m = int.tryParse(g.wd.substring(5, 7)); if (m != null) byMonth[m - 1]++; }
    final addedYear = lib.where((p) => DateTime.fromMillisecondsSinceEpoch(p.added).year == _year).length;
    final streak = _bestStreak(seenYear.map((g) => g.wd).toSet());
    final ratedYear = seenYear.where((g) => g.r > 0).toList();
    final avgR = ratedYear.isEmpty ? 0.0 : ratedYear.fold<int>(0, (s, g) => s + g.r) / ratedYear.length;
    // عام
    final cc = <String, int>{}; for (final p in lib) { if (p.country.isNotEmpty) cc[p.country] = (cc[p.country] ?? 0) + 1; }
    final topCc = (cc.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).toList();
    final ages = <String, int>{'18–24': 0, '25–29': 0, '30–34': 0, '35–39': 0, '40+': 0};
    for (final p in lib) { final a = p.age; if (a == null) continue; final k = a < 25 ? '18–24' : a < 30 ? '25–29' : a < 35 ? '30–34' : a < 40 ? '35–39' : '40+'; ages[k] = ages[k]! + 1; }
    final rd = List<int>.filled(5, 0); for (final p in lib) { if (p.rating > 0) rd[(p.rating.ceil() - 1).clamp(0, 4)]++; }

    return Scaffold(appBar: AppBar(title: const Text('الإحصائيات')), body: ListView(padding: const EdgeInsets.fromLTRB(S.s4, 0, S.s4, 80), children: [
      // ---------- ملخّص السنة ----------
      Container(
        padding: const EdgeInsets.all(S.s4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(S.rXl), gradient: const LinearGradient(colors: [Color(0xFF3A1B33), Color(0xFF16101F)], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: C.gold.withValues(alpha: .35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const AppLogo(size: 30), const SizedBox(width: 8), Expanded(child: GradientText('ملخّص $_year', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
            DropdownButton<int>(value: _year, underline: const SizedBox(), dropdownColor: C.bg2, items: [for (final yy in (years.whereType<int>().toList()..sort((a, b) => b.compareTo(a)))) DropdownMenuItem(value: yy, child: Text('$yy'))], onChanged: (v) => setState(() => _year = v!))]),
          const SizedBox(height: S.s3),
          Wrap(spacing: S.s3, runSpacing: S.s3, children: [
            _big('${seenYear.length}', 'عمل شاهدته'), _big('$addedYear', 'ممثلة أضفتها'), _big('$streak', 'أطول سلسلة أيام'), _big(avgR == 0 ? '—' : avgR.toStringAsFixed(1), 'متوسط تقييمك'),
          ]),
          if (topP.isNotEmpty) ...[
            const SizedBox(height: S.s4), const Text('الأكثر مشاهدة', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)), const SizedBox(height: S.s2),
            SizedBox(height: 120, child: ListView(scrollDirection: Axis.horizontal, children: [for (final (p, n) in topP) Padding(padding: const EdgeInsetsDirectional.only(end: S.s3), child: GestureDetector(onTap: () => context.push('/p/${p.id}'), child: Column(children: [
              ClipOval(child: SizedBox(width: 72, height: 72, child: Photo(p.cover, name: p.name, fallbacks: p.coverFallbacks))), const SizedBox(height: 4),
              SizedBox(width: 80, child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))), Text('$n عمل', style: const TextStyle(color: C.muted, fontSize: 11)),
            ])))])),
          ],
          if (topSt.isNotEmpty) ...[const SizedBox(height: S.s2), Text('الاستوديو الأول: ${topSt.first.key} (${topSt.first.value})', style: const TextStyle(color: C.muted))],
          const SizedBox(height: S.s4), const Text('المشاهدة شهريًا', style: TextStyle(color: C.gold2, fontWeight: FontWeight.w700)), const SizedBox(height: S.s2),
          _bars(byMonth.map((v) => v.toDouble()).toList(), const ['ين', 'فب', 'مر', 'أب', 'ما', 'يو', 'يل', 'أغ', 'سب', 'أك', 'نو', 'دي']),
        ]),
      ),
      SectionHeader('مكتبتك', sub: '${lib.length} ممثلة · ${works.length} عمل · ${works.where((g) => g.seen).length} شاهدته'),
      _card('التقييمات', _bars(rd.map((v) => v.toDouble()).toList(), const ['1★', '2★', '3★', '4★', '5★'])),
      _card('الأعمار', _bars(ages.values.map((v) => v.toDouble()).toList(), ages.keys.toList())),
      if (topCc.isNotEmpty) _card('البلدان', Column(children: [for (final e in topCc) _hbar(e.key, e.value, topCc.first.value)])),
      _card('حالة الأعمال', Column(children: [
        _hbar('شاهدتها', works.where((g) => g.seen).length, max(1, works.length)),
        _hbar('للمشاهدة', works.where((g) => g.q && !g.seen).length, max(1, works.length)),
        _hbar('قادمة', works.where((g) => g.isUpcoming).length, max(1, works.length)),
      ])),
    ]));
  }

  static int _bestStreak(Set<String> days) {
    final ds = days.map(DateTime.tryParse).whereType<DateTime>().toList()..sort();
    var best = 0, cur = 0; DateTime? prev;
    for (final d in ds) { cur = (prev != null && d.difference(prev).inDays == 1) ? cur + 1 : 1; best = max(best, cur); prev = d; }
    return best;
  }
  Widget _big(String v, String l) => SizedBox(width: 130, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.gold2)), Text(l, style: const TextStyle(color: C.muted))]));
  Widget _card(String t, Widget c) => Padding(padding: const EdgeInsets.only(bottom: S.s3), child: Card(child: Padding(padding: const EdgeInsets.all(S.s4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: S.s3), c]))));
  Widget _bars(List<double> v, List<String> labels) {
    final mx = v.fold<double>(0, max);
    return SizedBox(height: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (var i = 0; i < v.length; i++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (v[i] > 0) Text('${v[i].toInt()}', style: const TextStyle(fontSize: 10, color: C.muted)),
      AnimatedContainer(duration: S.slow, curve: S.ease, height: mx == 0 ? 2 : max(2, 80 * v[i] / mx), decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(6))),
      const SizedBox(height: 4), Text(labels[i], style: const TextStyle(fontSize: 10, color: C.muted)),
    ])))]));
  }
  Widget _hbar(String l, int v, int mx) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
    SizedBox(width: 80, child: Text(l, style: const TextStyle(color: C.muted))),
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: mx == 0 ? 0 : v / mx, minHeight: 10, backgroundColor: C.surface2, color: C.gold))),
    SizedBox(width: 44, child: Text('$v', textAlign: TextAlign.end)),
  ]));
}
