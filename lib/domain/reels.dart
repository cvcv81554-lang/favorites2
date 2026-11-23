import 'dart:math';

import 'sanitize.dart';
import 'work_taste.dart';
import 'works.dart';

/// «مقاطع»: إعلانات الأعمال الرسمية لممثلاتك في واجهة رأسية — بخوارزمية محلية تتعلم من سلوكك (لا يُرسل شيء لأي جهة).

/// [photo]: «مقطع صور» بديل لعمل مقطعه محجوب على شبكتك (صورة العمل + صور ممثلاته بحركة بطيئة) — مُعلَّم بوضوح.
class Reel {
  final WorkGroup g; final String url, why; final bool explore, photo; final List<String> images;
  const Reel(this.g, this.url, this.why, {this.explore = false, this.photo = false, this.images = const []});
  String get key => g.key;
}

/// إشارات المشاهدة المحفوظة على الجهاز.
class ReelSignals {
  /// المقطع ⇒ {n: مرات الظهور، w: أعلى نسبة مشاهدة، l: إعجاب، h: مخفي}
  final Map<String, Map<String, num>> clips;
  /// «pf:<ممثلة>» / «st:<استوديو>» ⇒ ميل متعلَّم (−2..2)
  final Map<String, double> aff;
  const ReelSignals(this.clips, this.aff);
  factory ReelSignals.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ReelSignals({for (final e in ((m['c'] as Map?) ?? const {}).entries) '${e.key}': Map<String, num>.from(e.value as Map)},
      {for (final e in ((m['a'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()});
  }
  Map<String, dynamic> toJson() => {'c': clips, 'a': aff};
}

Iterable<String> _affKeys(WorkGroup g) sync* { for (final p in g.who) { yield 'pf:${p.id}'; } if (g.s.trim().isNotEmpty) yield 'st:${norm(g.s)}'; }

/// تحديث بعد مشاهدة مقطع: [frac] نسبة ما شوهد (قد تتجاوز 1 عند الإعادة)، [like] إعجاب.
/// إكمال/إعادة/إعجاب ⇒ ميل إيجابي لممثلاته واستوديوه؛ تخطٍّ سريع (< 15٪) ⇒ ميل سلبي خفيف.
ReelSignals recordView(ReelSignals s, WorkGroup g, {required double frac, bool like = false}) {
  final c = {...s.clips}; final a = {...s.aff};
  final m = {...?c[g.key]};
  m['n'] = (m['n'] ?? 0) + 1; m['w'] = max((m['w'] ?? 0).toDouble(), frac); if (like) m['l'] = 1;
  c[g.key] = m;
  final sig = (frac >= 1.8 ? .7 : frac >= .9 ? .5 : frac >= .5 ? .2 : frac < .15 ? -.35 : 0.0) + (like ? .9 : 0);
  for (final k in _affKeys(g)) { a[k] = ((a[k] ?? 0) * .97 + sig).clamp(-2.0, 2.0); }
  return ReelSignals(c, a);
}

/// «أقل منها» / «أقل من هذا الاستوديو» / إخفاء المقطع.
ReelSignals dislike(ReelSignals s, {String? performerId, String? studio, String? hideKey}) {
  final a = {...s.aff}; final c = {...s.clips};
  if (performerId != null) a['pf:$performerId'] = -2;
  if (studio != null) a['st:${norm(studio)}'] = -2;
  if (hideKey != null) c[hideKey] = {...?c[hideKey], 'h': 1};
  return ReelSignals(c, a);
}

/// ترتيب المقاطع: ذوقك في الأعمال + ميلك المتعلَّم هنا + المفضلة + الحداثة − ما رأيته كثيرًا،
/// ثم تشكيل الخلاصة: ~80٪ الأفضل و~20٪ استكشاف (ممثلات/استوديوهات أقل ظهورًا)، ولا تتكرر ممثلة خلال 3 مقاطع متتالية.
/// [playable]: هل يعمل الخادم (أو المقطع محفوظ)؛ [isCached]: محفوظ على الجهاز (يُفضَّل قليلًا: يعمل فورًا)؛
/// [photoFallback]: ما لا يعمل يصبح «مقطع صور» بأولوية أقل بدل أن يختفي.
List<Reel> rankReels(List<WorkGroup> all, WorkTaste t, ReelSignals sig, {bool favsOnly = true, int seed = 0, int n = 80, bool Function(String url)? playable, bool Function(String url)? isCached, bool photoFallback = false}) {
  final pool = <(WorkGroup, double, String)>[];
  for (final g in all) {
    if (g.tr.isEmpty || g.who.isEmpty) continue;
    final asPhoto = playable != null && !playable(g.tr);
    if (asPhoto && (!photoFallback || g.p.isEmpty)) continue;   // خادم محجوب على شبكتك أو لا يُشغَّل
    if (favsOnly && !g.who.any((p) => p.fav || p.rating >= 4)) continue;
    final c = sig.clips[g.key];
    if (c?['h'] == 1) continue;
    var score = 0.0; String why = '';
    final st = t.keys['st:${norm(g.s)}'];
    if (st != null) score += st.score;
    for (final p in g.who) { final k = t.keys['pf:${p.id}']; if (k != null) score += k.score * 1.2; }
    for (final x in g.tg) { final k = t.keys['tg:${norm(x)}']; if (k != null) score += k.score * .3; }
    if (g.who.any((p) => p.fav)) score += .35;
    var aff = 0.0; String? affWhy;
    for (final k in _affKeys(g)) {
      final v = sig.aff[k] ?? 0; aff += v;
      if (v > .6 && affWhy == null) affWhy = k.startsWith('pf:') ? 'لأنك تكمل مقاطع ${g.who.firstWhere((p) => 'pf:${p.id}' == k, orElse: () => g.who.first).name}' : 'لأنك تحب مقاطع ${g.s}';
    }
    score += aff * .6;
    final yr = int.tryParse(g.y) ?? 0; if (yr > 0) score += max(0, yr - 2015) * .02;
    score -= ((c?['n'] ?? 0) * .35).toDouble();                       // ما رأيته ينزل تدريجيًا
    if (c?['l'] == 1) score += .2;
    if (!asPhoto && isCached != null && isCached(g.tr)) score += .25;   // جاهز على الجهاز: بلا انتظار
    if (asPhoto) score -= .6;                                             // المقاطع الحقيقية أولًا
    why = affWhy ?? (st != null && st.score > .2 ? 'من ${g.s} الذي تحبه' : g.who.any((p) => p.fav) ? 'من مفضلاتك: ${g.who.firstWhere((p) => p.fav).name}' : 'من مكتبتك');
    pool.add((g, score, asPhoto ? '📷 صور — مقطعه محجوب على شبكتك' : why));
  }
  if (pool.isEmpty) return const [];
  pool.sort((a, b) => b.$2.compareTo(a.$2));
  final rnd = Random(seed);
  final explorePool = pool.where((x) => x.$1.who.every((p) => (sig.aff['pf:${p.id}'] ?? 0).abs() < .3)).toList()..shuffle(rnd);
  final used = <String>{}; final out = <Reel>[]; final recent = <String>[];
  bool fits((WorkGroup, double, String) x) => !used.contains(x.$1.key) && !x.$1.who.any((p) => recent.contains(p.id));
  var i = 0, e = 0;
  while (out.length < n && (i < pool.length || e < explorePool.length)) {
    final exploreTurn = rnd.nextDouble() < .2 && e < explorePool.length;
    (WorkGroup, double, String)? pick;
    if (exploreTurn) { while (e < explorePool.length && pick == null) { final x = explorePool[e++]; if (fits(x)) pick = x; } }
    if (pick == null) {
      for (var k = i; k < pool.length; k++) { if (fits(pool[k])) { pick = pool[k]; if (k == i) i++; break; } }
      if (pick == null) { // لا يناسب التنويع: نسمح بالتكرار القريب بدل التوقف
        while (i < pool.length && used.contains(pool[i].$1.key)) { i++; }
        if (i >= pool.length) break;
        pick = pool[i++];
      }
    }
    used.add(pick.$1.key);
    final ph = pick.$3.startsWith('📷');
    out.add(Reel(pick.$1, pick.$1.tr, ph ? pick.$3 : exploreTurn ? 'استكشاف: شيء مختلف قليلًا' : pick.$3, explore: exploreTurn && !ph, photo: ph,
      images: ph ? [pick.$1.p, for (final p in pick.$1.who) ...p.photos.take(2)].where((x) => x.isNotEmpty).toList() : const []));
    recent.addAll(pick.$1.who.map((p) => p.id)); while (recent.length > 3) { recent.removeAt(0); }
  }
  return out;
}


// ===================== الخوادم التي تعمل على شبكتك =====================

String hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

/// حالة خادم محفوظة: {ok: يعمل؟، dl: يحتاج تنزيلًا، t: وقت الفحص، why: السبب}. المحجوب يُعاد فحصه بعد 6 ساعات، والعامل بعد 14 يومًا.
bool hostStale(Map? h, int now) => h == null || now - ((h['t'] as num?) ?? 0) > (h['ok'] == true ? 14 * 86400000 : 6 * 3600000);
/// يُعرض المقطع إن كان خادمه يعمل أو لم يُفحص بعد (يُفحص عند التشغيل).
bool hostUsable(Map<String, dynamic> hosts, String url) => (hosts[hostOf(url)] as Map?)?['ok'] != false;
/// خطأ تشغيل يعني حجب الشبكة (لا خطأ في المقطع نفسه).
bool looksBlocked(String err) => RegExp(r'TLS|-1200|-1005|reset|Handshake|connection was lost|closed', caseSensitive: false).hasMatch(err);
