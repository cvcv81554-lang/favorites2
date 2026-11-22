import 'dart:math';

import 'sanitize.dart';
import 'works.dart';

/// ذوقك في **الأعمال** (محلي بالكامل — من تقييماتك ومشاهداتك فقط، بلا إنترنت ولا تحليل صور):
/// الاستوديوهات والوسوم والممثلات في الأعمال التي أحببتها ⇒ ترتيب أعمال لم تشاهدها بعد، مع سبب لكل اقتراح.

/// إشارة كل عمل لذوقك: تقييم عالٍ قوي، مشاهدة/مفضلة متوسطة، «للمشاهدة» خفيفة، تقييم منخفض سلبي.
double workSignal(WorkGroup g) {
  if (g.r >= 1) return (g.r - 2.5) / 1.5;          // 5⇒+1.67، 4⇒+1، 3⇒+.33، 2⇒−.33، 1⇒−1
  if (g.rc.isNotEmpty) { final a = g.rc.values.reduce((x, y) => x + y) / g.rc.length; return (a - 2.5) / 1.5; }   // التقييم بالمعايير
  var s = 0.0;
  if (g.seen) s += .6;
  if (g.fav) s += .8;
  if (g.q) s += .3;
  return s;
}

class KeyStat { final String key, label; final double sum; final int n; final double avgR; const KeyStat(this.key, this.label, this.sum, this.n, this.avgR);
  /// درجة مُلطّفة (لا يقفز مفتاح بعمل واحد).
  double get score => sum / (n + 2);
}

class WorkTaste {
  final Map<String, KeyStat> keys; final int signals;
  const WorkTaste(this.keys, this.signals);
  /// يكفي للاقتراح: 5 أعمال على الأقل قيّمتها أو شاهدتها.
  bool get sufficient => signals >= 5;
  List<KeyStat> top(String prefix, {int k = 5}) => (keys.values.where((x) => x.key.startsWith(prefix) && x.score > .15 && x.n >= 2).toList()..sort((a, b) => b.score.compareTo(a.score))).take(k).toList();
}

/// مفاتيح العمل: الاستوديو، الوسوم، ممثلاته.
Iterable<(String, String)> _keysOf(WorkGroup g) sync* {
  if (g.s.trim().isNotEmpty) yield ('st:${norm(g.s)}', g.s.trim());
  for (final t in g.tg.take(12)) { if (t.trim().isNotEmpty) yield ('tg:${norm(t)}', t.trim()); }
  for (final p in g.who) { yield ('pf:${p.id}', p.name); }
}

WorkTaste buildWorkTaste(Iterable<WorkGroup> all) {
  final sum = <String, double>{}, n = <String, int>{}, label = <String, String>{}, rSum = <String, int>{}, rN = <String, int>{};
  var signals = 0;
  for (final g in all) {
    final s = workSignal(g); if (s == 0) continue;
    signals++;
    for (final (k, l) in _keysOf(g)) {
      sum[k] = (sum[k] ?? 0) + s; n[k] = (n[k] ?? 0) + 1; label[k] ??= l;
      if (g.r > 0) { rSum[k] = (rSum[k] ?? 0) + g.r; rN[k] = (rN[k] ?? 0) + 1; }
    }
  }
  return WorkTaste({for (final k in sum.keys) k: KeyStat(k, label[k]!, sum[k]!, n[k]!, (rN[k] ?? 0) == 0 ? 0 : rSum[k]! / rN[k]!)}, signals);
}

class WorkPick { final WorkGroup g; final double score; final List<String> why; const WorkPick(this.g, this.score, this.why); }

/// أعمال لم تشاهدها (صدرت) مرتبة حسب ذوقك — لا اقتراح بلا سبب حقيقي.
List<WorkPick> recommendWorks(Iterable<WorkGroup> all, WorkTaste t, {int limit = 60}) {
  final out = <WorkPick>[];
  final t0 = todayStr();
  for (final g in all) {
    if (g.seen || g.isUpcoming || g.r > 0 || g.rc.isNotEmpty) continue;
    if (g.date.isNotEmpty && g.date.compareTo(t0) > 0) continue;
    var score = 0.0; final why = <String>[];
    final st = t.keys['st:${norm(g.s)}'];
    if (st != null && st.score > .15) {
      score += st.score * 1.0;
      why.add(st.avgR >= 3.5 ? 'من ${st.label} — متوسط تقييمك لأعماله ${st.avgR.toStringAsFixed(1)}' : 'من ${st.label} الذي تشاهد أعماله كثيرًا');
    }
    final tags = [for (final x in g.tg) t.keys['tg:${norm(x)}']].whereType<KeyStat>().where((k) => k.score > .15).toList()..sort((a, b) => b.score.compareTo(a.score));
    if (tags.isNotEmpty) {
      score += tags.take(4).fold<double>(0, (s, k) => s + k.score * .5);
      why.add('وسوم تحبها: ${tags.take(3).map((k) => k.label).join('، ')}');
    }
    final ps = [for (final p in g.who) (p, t.keys['pf:${p.id}'])].where((x) => x.$2 != null && x.$2!.score > .15).toList()..sort((a, b) => b.$2!.score.compareTo(a.$2!.score));
    final favs = g.who.where((p) => p.fav).toList();
    if (ps.isNotEmpty) { score += ps.first.$2!.score * 1.2; why.add('مع ${ps.first.$1.name} التي أحببت أعمالها'); }
    else if (favs.isNotEmpty) { score += .25; why.add('مع ${favs.first.name} من مفضلاتك'); }
    if (why.isEmpty) continue;
    // أحدث قليلًا أولًا عند التعادل
    final yr = int.tryParse(g.y) ?? 0; if (yr > 0) score += max(0, (yr - 2000)) * .002;
    out.add(WorkPick(g, score, why));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
