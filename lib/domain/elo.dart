import 'dart:math';

import 'performer.dart';

/// المواجهة: Elo بـ K=32 (كالتطبيق السابق). يعيد التقييمين الجديدين.
(double, double) eloUpdate(double winner, double loser, {double k = 32}) {
  final ew = 1 / (1 + pow(10, (loser - winner) / 400));
  return (winner + k * (1 - ew), loser - k * (1 - ew));
}

double eloOf(Performer p) => (p.raw['elo'] as num?)?.toDouble() ?? 1000;
int duelsOf(Performer p) => (p.raw['duels'] as num?)?.toInt() ?? 0;

/// اختيار زوج: الأقل مواجهات من 5 عشوائيات، ثم الأقرب تقييمًا من 9 أخريات، مع تجنب الزوج السابق.
(Performer, Performer)? pickPair(List<Performer> pool, Random rnd, {Set<String> last = const {}}) {
  if (pool.length < 2) return null;
  final a5 = [for (var i = 0; i < 5; i++) pool[rnd.nextInt(pool.length)]]..sort((x, y) => duelsOf(x).compareTo(duelsOf(y)));
  final a = a5.first;
  final others = [for (var i = 0; i < 9; i++) pool[rnd.nextInt(pool.length)]].where((b) => b.id != a.id && !(last.contains(a.id) && last.contains(b.id))).toList()
    ..sort((x, y) => (eloOf(x) - eloOf(a)).abs().compareTo((eloOf(y) - eloOf(a)).abs()));
  if (others.isEmpty) { final b = pool.firstWhere((x) => x.id != a.id); return (a, b); }
  return (a, others.first);
}

/// المستوى التلقائي من التقييم.
String tierFromRating(double r) => r >= 4.75 ? 'S' : r >= 4 ? 'A' : r >= 3 ? 'B' : r >= 2 ? 'C' : r > 0 ? 'D' : '';

/// اكتمال السجل (7 فحوص كالقديم).
List<(String, bool)> completeness(Performer p) => [
  ('صورة', p.photos.isNotEmpty), ('تاريخ ميلاد كامل', RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p.birth)), ('البلد', p.country.isNotEmpty),
  ('رابط مصدر', p.stashId.isNotEmpty || p.pdbId.isNotEmpty), ('تقييم', p.rating > 0), ('أعمال', p.works.isNotEmpty), ('وسوم', p.tags.isNotEmpty),
];
