import 'performer.dart';
import 'works.dart';

/// «يومياتي»: ملخص الشهر، الأهداف والمراحل، وتقويم المشاهدة — كله من تاريخ المشاهدة (wd) على جهازك فقط.

String _ym(int y, int m) => '$y-${'$m'.padLeft(2, '0')}';

class MonthReview {
  final int year, month, watched, prevWatched, added, rated, activeDays;
  final double avgRating;
  final List<(Performer, int)> topPerformers;
  final List<(String, int)> topStudios, topTags;
  final List<Performer> firstTime;      // أول مرة تشاهد لها شيئًا هذا الشهر
  final String bestDay; final int bestDayCount;
  const MonthReview({required this.year, required this.month, required this.watched, required this.prevWatched, required this.added, required this.rated, required this.activeDays,
    required this.avgRating, required this.topPerformers, required this.topStudios, required this.topTags, required this.firstTime, required this.bestDay, required this.bestDayCount});
  int get delta => watched - prevWatched;
}

MonthReview monthReview(List<WorkGroup> works, List<Performer> lib, int year, int month) {
  final key = _ym(year, month);
  final pm = month == 1 ? _ym(year - 1, 12) : _ym(year, month - 1);
  final seen = works.where((g) => g.seen && g.wd.startsWith(key)).toList();
  final prev = works.where((g) => g.seen && g.wd.startsWith(pm)).length;
  final byP = <String, (Performer, int)>{}; final bySt = <String, int>{}; final byTg = <String, int>{}; final byDay = <String, int>{};
  for (final g in seen) {
    for (final p in g.who) { byP[p.id] = (p, (byP[p.id]?.$2 ?? 0) + 1); }
    if (g.s.isNotEmpty) bySt[g.s] = (bySt[g.s] ?? 0) + 1;
    for (final t in g.tg) { byTg[t] = (byTg[t] ?? 0) + 1; }
    byDay[g.wd] = (byDay[g.wd] ?? 0) + 1;
  }
  // أول مرة: لا مشاهدة لها قبل هذا الشهر
  final before = <String>{for (final g in works) if (g.seen && g.wd.isNotEmpty && g.wd.compareTo(key) < 0) ...g.who.map((p) => p.id)};
  final first = [for (final e in byP.values) if (!before.contains(e.$1.id)) e.$1];
  final rated = seen.where((g) => g.r > 0).toList();
  final best = (byDay.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key))).firstOrNull;
  List<(String, int)> top(Map<String, int> m, int n) => (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).map((e) => (e.key, e.value)).toList();
  return MonthReview(year: year, month: month, watched: seen.length, prevWatched: prev,
    added: lib.where((p) { final d = DateTime.fromMillisecondsSinceEpoch(p.added); return d.year == year && d.month == month; }).length,
    rated: rated.length, avgRating: rated.isEmpty ? 0 : rated.fold<int>(0, (s, g) => s + g.r) / rated.length, activeDays: byDay.length,
    topPerformers: (byP.values.toList()..sort((a, b) => b.$2.compareTo(a.$2))).take(5).toList(), topStudios: top(bySt, 5), topTags: top(byTg, 6),
    firstTime: first, bestDay: best?.key ?? '', bestDayCount: best?.value ?? 0);
}

/// تقويم المشاهدة: عدد ما شاهدته في كل يوم لآخر [days] يومًا (مفتاح yyyy-mm-dd).
Map<String, int> watchHeatmap(List<WorkGroup> works, {int days = 182, DateTime? now}) {
  final end = now ?? DateTime.now(); final start = DateTime(end.year, end.month, end.day).subtract(Duration(days: days - 1));
  final s0 = start.toIso8601String().substring(0, 10);
  final out = <String, int>{};
  for (final g in works) { if (g.seen && g.wd.length == 10 && g.wd.compareTo(s0) >= 0) out[g.wd] = (out[g.wd] ?? 0) + 1; }
  return out;
}

/// أطول سلسلة أيام متتالية وسلسلتك الحالية.
(int best, int current) streaks(Iterable<String> days, {DateTime? now}) {
  final set = days.where((d) => d.length == 10).toSet(); if (set.isEmpty) return (0, 0);
  final ds = set.map(DateTime.parse).toList()..sort();
  var best = 1, run = 1;
  for (var i = 1; i < ds.length; i++) { run = ds[i].difference(ds[i - 1]).inDays == 1 ? run + 1 : 1; if (run > best) best = run; }
  final t = now ?? DateTime.now(); var d = DateTime(t.year, t.month, t.day); var cur = 0;
  if (!set.contains(d.toIso8601String().substring(0, 10))) d = d.subtract(const Duration(days: 1));   // اليوم لم ينتهِ بعد
  while (set.contains(d.toIso8601String().substring(0, 10))) { cur++; d = d.subtract(const Duration(days: 1)); }
  return (best, cur);
}

/// مراحل (مثل Letterboxd): أعمالها المنشورة التي شاهدتها من مجموعها — للمفضلات اللاتي لهن 5 أعمال فأكثر، الأقرب للاكتمال أولًا.
List<({Performer p, int seen, int total})> performerMilestones(List<WorkGroup> works, List<Performer> lib, {int minTotal = 5}) {
  final byP = <String, (int, int)>{};
  for (final g in works) {
    if (g.isUpcoming) continue;
    for (final p in g.who) { final x = byP[p.id] ?? (0, 0); byP[p.id] = (x.$1 + (g.seen ? 1 : 0), x.$2 + 1); }
  }
  final out = [for (final p in lib) if ((p.fav || p.rating >= 4) && (byP[p.id]?.$2 ?? 0) >= minTotal) (p: p, seen: byP[p.id]!.$1, total: byP[p.id]!.$2)];
  out.sort((a, b) { final fa = a.seen / a.total, fb = b.seen / b.total; return fb.compareTo(fa); });
  return out;
}

/// المرحلة التالية لمجموع ما شاهدته (10، 25، 50، 100، 250، 500، 1000…).
(int next, int prev) nextMilestone(int n) {
  const steps = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000];
  var prev = 0;
  for (final s in steps) { if (n < s) return (s, prev); prev = s; }
  return ((n ~/ 5000 + 1) * 5000, prev);
}
