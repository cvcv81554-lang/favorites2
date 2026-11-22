import 'dart:math';

import 'performer.dart';
import 'sanitize.dart';
import 'taste.dart';
import 'work_taste.dart';
import 'works.dart';

// ===================== 1) مسيرة الممثلة =====================

class CareerYear { final int year, count, seen; final double avgR; final List<String> studios; const CareerYear(this.year, this.count, this.seen, this.avgR, this.studios); }
class Career {
  final List<CareerYear> years; final int? start, first, last, peak; final List<(String, int)> topStudios; final double? trend;   // trend: تغيّر متوسط تقييمك (الأحدث − الأقدم)
  const Career(this.years, this.start, this.first, this.last, this.peak, this.topStudios, this.trend);
  bool get isEmpty => years.isEmpty;
}

/// مسيرتها سنة بسنة من أعمالها (بتاريخ أو سنة): العدد، ما شاهدته، متوسط تقييمك، أكثر الاستوديوهات.
Career careerOf(Performer p) {
  final by = <int, List<Map<String, dynamic>>>{};
  for (final w in p.works) {
    final y = int.tryParse('${w['d'] ?? ''}'.length >= 4 ? '${w['d']}'.substring(0, 4) : '${w['y'] ?? ''}');
    if (y == null || y < 1970 || y > DateTime.now().year + 2) continue;
    (by[y] ??= []).add(w);
  }
  final years = <CareerYear>[];
  final studioN = <String, (String, int)>{};
  for (final y in (by.keys.toList()..sort())) {
    final l = by[y]!; final st = <String, int>{};
    for (final w in l) { final s = '${w['s'] ?? ''}'.trim(); if (s.isEmpty) continue; st[s] = (st[s] ?? 0) + 1; final k = norm(s); studioN[k] = (studioN[k]?.$1 ?? s, (studioN[k]?.$2 ?? 0) + 1); }
    final rs = [for (final w in l) if (w['r'] is num && (w['r'] as num) > 0) (w['r'] as num).toDouble()];
    years.add(CareerYear(y, l.length, l.where((w) => w['w'] == 1 || w['w'] == true).length, rs.isEmpty ? 0 : rs.reduce((a, b) => a + b) / rs.length,
      (st.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) => e.key).toList()));
  }
  if (years.isEmpty) return const Career([], null, null, null, null, [], null);
  final peak = years.reduce((a, b) => b.count > a.count ? b : a).year;
  final rated = years.where((y) => y.avgR > 0).toList();
  final trend = rated.length >= 2 ? rated.last.avgR - rated.first.avgR : null;
  return Career(years, (p.raw['cs'] as num?)?.toInt(), years.first.year, years.last.year, peak,
    (studioN.values.toList()..sort((a, b) => b.$2.compareTo(a.$2))).take(5).toList(), trend);
}

// ===================== 2) سهرة مشاهدة =====================

enum EveningMood { taste, favs, fresh, newFace, random }
const eveningMoods = {EveningMood.taste: '✨ حسب ذوقي', EveningMood.favs: '♥ مفضلاتي', EveningMood.fresh: '🆕 الأحدث', EveningMood.newFace: '👀 ممثلة جديدة عليّ', EveningMood.random: '🎲 مفاجأة'};

/// ثلاثة أعمال لم تشاهدها (صدرت) حسب المزاج والمدة؛ [seed] يغيّر الاختيار عند «غيّرها».
List<WorkPick> eveningPicks(List<WorkGroup> all, WorkTaste t, {EveningMood mood = EveningMood.taste, int maxMinutes = 0, int seed = 0, int n = 3}) {
  final t0 = todayStr();
  final watchedP = <String>{for (final g in all) if (g.seen) for (final p in g.who) p.id};
  bool ok(WorkGroup g) => !g.seen && !g.isUpcoming && (g.date.isEmpty || g.date.compareTo(t0) <= 0) && (maxMinutes == 0 || (g.du > 0 && g.du <= maxMinutes));
  final ranked = {for (final x in recommendWorks(all, t, limit: 400)) x.g.key: x};
  List<WorkPick> pool;
  switch (mood) {
    case EveningMood.taste: pool = ranked.values.where((x) => ok(x.g)).toList();
    case EveningMood.favs: pool = [for (final g in all) if (ok(g) && g.who.any((p) => p.fav)) ranked[g.key] ?? WorkPick(g, .1, ['مع ${g.who.firstWhere((p) => p.fav).name} من مفضلاتك'])]..sort((a, b) => b.score.compareTo(a.score));
    case EveningMood.fresh: pool = [for (final g in (all.where(ok).toList()..sort((a, b) => b.date.compareTo(a.date))).take(40)) ranked[g.key] ?? WorkPick(g, 0, ['صدر ${g.date.isEmpty ? 'حديثًا' : g.date}'])];
    case EveningMood.newFace: pool = [for (final g in all) if (ok(g) && g.who.isNotEmpty && g.who.every((p) => !watchedP.contains(p.id))) ranked[g.key] ?? WorkPick(g, 0, ['لم تشاهد لـ ${g.who.first.name} شيئًا بعد'])]..sort((a, b) => b.score.compareTo(a.score));
    case EveningMood.random: pool = [for (final g in all) if (ok(g)) ranked[g.key] ?? WorkPick(g, 0, ['اختيار عشوائي'])];
  }
  if (pool.isEmpty) return const [];
  // تنويع: من أفضل 15 (أو الكل للمفاجأة) بترتيب يتغير مع seed، وبلا تكرار ممثلة في نفس السهرة
  final top = mood == EveningMood.random ? [...pool] : pool.take(15).toList();
  top.shuffle(Random(seed));
  final out = <WorkPick>[]; final used = <String>{};
  for (final x in top) { if (out.length >= n) break; if (x.g.who.any((p) => used.contains(p.id))) continue; out.add(x); used.addAll(x.g.who.map((p) => p.id)); }
  for (final x in top) { if (out.length >= n) break; if (!out.contains(x)) out.add(x); }
  return out;
}

// ===================== 3) التقييم بمعايير =====================

const workCriteria = {'perf': 'الأداء', 'photo': 'التصوير', 'story': 'القصة'};
/// متوسط المعايير (0 إن لم تُقيَّم).
double criteriaAvg(Map<String, dynamic>? rc) {
  final v = [for (final k in workCriteria.keys) if (rc?[k] is num && (rc![k] as num) > 0) (rc[k] as num).toDouble()];
  return v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
}

// ===================== 4) لماذا أحبها؟ =====================

/// ما تشترك فيه مع بقية مفضلاتك (من البيانات الموثّقة فقط): (السمة، كم مفضلة أخرى تشاركها، النسبة).
List<(String, int, double)> sharedTraits(Map<String, Object> her, List<Map<String, Object>> others) {
  final out = <(String, int, double)>[];
  if (others.isEmpty) return out;
  her.forEach((k, v) {
    if (v is! String) return;
    final n = others.where((o) => o[k] == v).length;
    if (n > 0) out.add(('${fieldNames[k] ?? k}: ${attrLabel(k, v)}', n, n / others.length));
  });
  for (final k in const ['height', 'age']) {
    final v = her[k]; if (v is! double) continue;
    final n = others.where((o) => o[k] is double && ((o[k] as double) - v).abs() <= (k == 'height' ? 4 : 3)).length;
    if (n > 0) out.add((k == 'height' ? 'الطول قريب من ${v.round()} سم' : 'العمر قريب من ${v.round()}', n, n / others.length));
  }
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

/// الأقرب إليها هي تحديدًا (من مرشحات الاقتراح): درجة التشابه مع ملف من ممثلة واحدة.
List<(T, double)> closestTo<T>(Map<String, Object> her, List<(T, Map<String, Object>)> cands, {int k = 10}) {
  final prof = buildProfile([her, her, her]);   // ملف من ممثلة واحدة (التكرار يجعل خصائصها «واضحة»)
  final l = [for (final c in cands) if (c.$2.isNotEmpty) (c.$1, similarity(prof, c.$2).score)]..sort((a, b) => b.$2.compareTo(a.$2));
  return l.take(k).toList();
}

// ===================== 5) خريطة الذوق =====================

/// متجه خصائص قابل للمقارنة: فئوية (واحد-ساخن) + رقمية مطبّعة.
List<String> _vocab(List<Map<String, Object>> fs) => {for (final f in fs) for (final e in f.entries) if (e.value is String) '${e.key}=${e.value}'}.toList()..sort();
const _numScale = {'height': 10.0, 'age': 6.0, 'career_start_year': 5.0, 'cup': 1.5, 'waist_size': 4.0, 'hip_size': 4.0};

/// إسقاط ثنائي الأبعاد (تحليل المكوّنات الرئيسية) — نقاط متقاربة = خصائص متقاربة. يعيد (x,y) بين −1 و1.
List<(double, double)> tasteMap(List<Map<String, Object>> fs) {
  if (fs.isEmpty) return const [];
  final voc = _vocab(fs);
  final means = <String, double>{};
  for (final k in _numScale.keys) { final v = [for (final f in fs) if (f[k] is double) f[k] as double]; if (v.isNotEmpty) means[k] = v.reduce((a, b) => a + b) / v.length; }
  final dims = [...voc, ...means.keys.map((k) => '#$k')];
  if (dims.isEmpty) return [for (final _ in fs) (0.0, 0.0)];
  List<double> vec(Map<String, Object> f) => [
    for (final d in voc) () { final i = d.indexOf('='); return f[d.substring(0, i)] == d.substring(i + 1) ? 1.0 : 0.0; }(),
    for (final k in means.keys) f[k] is double ? ((f[k] as double) - means[k]!) / _numScale[k]! : 0.0,
  ];
  final x = [for (final f in fs) vec(f)];
  final n = x.length, m = dims.length;
  final mu = List<double>.generate(m, (j) => x.fold<double>(0, (s, r) => s + r[j]) / n);
  for (final r in x) { for (var j = 0; j < m; j++) { r[j] -= mu[j]; } }
  List<double> power(List<double>? orth) {
    var v = List<double>.generate(m, (j) => 1.0 / (j + 1));
    for (var it = 0; it < 60; it++) {
      final xv = [for (final r in x) () { var s = 0.0; for (var j = 0; j < m; j++) { s += r[j] * v[j]; } return s; }()];
      final nv = List<double>.filled(m, 0);
      for (var i = 0; i < n; i++) { for (var j = 0; j < m; j++) { nv[j] += x[i][j] * xv[i]; } }
      if (orth != null) { final d = List.generate(m, (j) => nv[j] * orth[j]).fold<double>(0, (a, b) => a + b); for (var j = 0; j < m; j++) { nv[j] -= d * orth[j]; } }
      final norm2 = sqrt(nv.fold<double>(0, (a, b) => a + b * b)); if (norm2 < 1e-12) return List.filled(m, 0);
      v = [for (final e in nv) e / norm2];
    }
    return v;
  }
  final a = power(null), b = power(a);
  final pts = [for (final r in x) (List.generate(m, (j) => r[j] * a[j]).fold<double>(0, (s, e) => s + e), List.generate(m, (j) => r[j] * b[j]).fold<double>(0, (s, e) => s + e))];
  final mx = pts.fold<double>(1e-9, (s, p) => max(s, max(p.$1.abs(), p.$2.abs())));
  return [for (final p in pts) (p.$1 / mx, p.$2 / mx)];
}

// ===================== 6) ذوقك عبر الزمن =====================

class TasteYear { final int year, added, watched; final List<String> traits, studios; const TasteYear(this.year, this.added, this.watched, this.traits, this.studios); }

/// كل سنة: من أضفت من المفضلات/المقيّمات وأبرز خصائصهن، وما شاهدته وأبرز استوديوهاته.
List<TasteYear> tasteOverTime(List<Performer> lib, List<WorkGroup> works, Map<String, Map<String, Object>> featsById) {
  final years = <int>{};
  final addedBy = <int, List<Performer>>{};
  for (final p in lib) {
    if (p.added <= 0 || p.isMinor || !(p.fav || p.rating >= 4)) continue;
    final y = DateTime.fromMillisecondsSinceEpoch(p.added).year; years.add(y); (addedBy[y] ??= []).add(p);
  }
  final watchedBy = <int, List<WorkGroup>>{};
  for (final g in works) { if (g.wd.length >= 4) { final y = int.tryParse(g.wd.substring(0, 4)); if (y != null) { years.add(y); (watchedBy[y] ??= []).add(g); } } }
  final out = <TasteYear>[];
  for (final y in (years.toList()..sort())) {
    final ps = addedBy[y] ?? const [];
    final cnt = <String, int>{};
    for (final p in ps) { featsById[p.id]?.forEach((k, v) { if (v is String && const ['hair_color', 'ethnicity', 'country', 'eye_color'].contains(k)) { final key = '${fieldNames[k]}: ${attrLabel(k, v)}'; cnt[key] = (cnt[key] ?? 0) + 1; } }); }
    final traits = (cnt.entries.where((e) => ps.length >= 2 && e.value / ps.length >= .5).toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) => e.key).toList();
    final st = <String, int>{}; for (final g in watchedBy[y] ?? const <WorkGroup>[]) { if (g.s.trim().isNotEmpty) st[g.s.trim()] = (st[g.s.trim()] ?? 0) + 1; }
    out.add(TasteYear(y, ps.length, (watchedBy[y] ?? const []).length, traits, (st.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3).map((e) => e.key).toList()));
  }
  return out;
}

// ===================== 7) ألبومات الحقب =====================

/// تقسيم صور ممثلة: لقطات المشاهد حسب سنة العمل (من رابط صورته)، والصور الشخصية وحدها.
/// [shots]: (رابط الصورة، النوع) — يعيد (عنوان القسم، الفهارس) مرتبة من الأحدث.
List<(String, List<int>)> eraAlbums(Performer p, List<(String, String)> shots) {
  final yearOf = <String, int>{};
  for (final w in p.works) {
    final u = '${w['p'] ?? ''}'; if (u.isEmpty) continue;
    final y = int.tryParse('${w['d'] ?? ''}'.length >= 4 ? '${w['d']}'.substring(0, 4) : '${w['y'] ?? ''}');
    if (y != null) yearOf[u] = y;
  }
  final by = <int, List<int>>{}; final portraits = <int>[], other = <int>[];
  for (var i = 0; i < shots.length; i++) {
    final y = yearOf[shots[i].$1];
    if (y != null) { (by[y] ??= []).add(i); } else if (shots[i].$2 == 'portrait') { portraits.add(i); } else { other.add(i); }
  }
  return [
    if (portraits.isNotEmpty) ('صور شخصية', portraits),
    for (final y in (by.keys.toList()..sort((a, b) => b.compareTo(a)))) ('$y', by[y]!),
    if (other.isNotEmpty) ('لقطات أخرى', other),
  ];
}
