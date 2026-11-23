import 'dart:math';

import 'sanitize.dart';
import 'work_taste.dart';
import 'works.dart';

/// «مقاطع»: إعلانات الأعمال الرسمية لممثلاتك في واجهة رأسية — بخوارزمية محلية تتعلم من سلوكك (لا يُرسل شيء لأي جهة).

/// [photo]: «مقطع صور» بديل لعمل مقطعه محجوب على شبكتك (صورة العمل + صور ممثلاته بحركة بطيئة) — مُعلَّم بوضوح.
/// [src]: المصدر الظاهر على المقطع؛ [start]/[len]: مقطع قصير من فيديو كامل (ثوانٍ، 0 = كامل)؛ [full]: فيديو كامل.
class Reel {
  final WorkGroup g; final String url, why, src; final bool explore, photo, full; final List<String> images; final int start, len;
  const Reel(this.g, this.url, this.why, {this.explore = false, this.photo = false, this.images = const [], this.src = 'ThePornDB · إعلان', this.start = 0, this.len = 0, this.full = false});
  String get key => '${g.key}${start > 0 ? '@$start' : ''}${full ? '#full' : ''}';
  Reel variant({int start = 0, int len = 0, bool full = false, String? src}) => Reel(g, url, why, explore: explore, src: src ?? this.src, start: start, len: len, full: full);
}

/// دمج خلاصتين بالتناوب (مقطعان من [b] لكل مقطع من [a] ما دام الاثنان متاحين)، بلا تكرار.
List<Reel> weave(List<Reel> a, List<Reel> b, {int bPerA = 2}) {
  final out = <Reel>[]; var i = 0, j = 0; final seen = <String>{};
  void add(Reel r) { if (seen.add(r.key)) out.add(r); }
  while (i < a.length || j < b.length) {
    if (i < a.length) add(a[i++]);
    for (var k = 0; k < bPerA && j < b.length; k++) { add(b[j++]); }
  }
  return out;
}

/// إشارات المشاهدة المحفوظة على الجهاز.
class ReelSignals {
  /// المقطع ⇒ {n: مرات الظهور، w: أعلى نسبة مشاهدة، l: إعجاب، h: مخفي}
  final Map<String, Map<String, num>> clips;
  /// «pf:<ممثلة>» / «st:<استوديو>» ⇒ ميل متعلَّم (−2..2)
  final Map<String, double> aff;
  /// آخر يوم طُبِّق فيه تلاشي الميول (أيام منذ 1970) — حقل اختياري جديد «d».
  final int day;
  const ReelSignals(this.clips, this.aff, [this.day = 0]);
  factory ReelSignals.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ReelSignals({for (final e in ((m['c'] as Map?) ?? const {}).entries) '${e.key}': Map<String, num>.from(e.value as Map)},
      {for (final e in ((m['a'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()}, (m['d'] as num?)?.toInt() ?? 0);
  }
  Map<String, dynamic> toJson() => {'c': clips, 'a': aff, if (day > 0) 'd': day};
}

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
int reelDay([DateTime? t]) => (t ?? DateTime.now()).millisecondsSinceEpoch ~/ 86400000;

/// تلاشي الاهتمام مع الوقت (مثل TikTok: الذوق القديم لا يحبسك): كل يوم ×0.985، عدا «أقل منها» الصريح (−2) يبقى.
ReelSignals decayReels(ReelSignals s, int today) {
  if (s.day == 0) return ReelSignals(s.clips, s.aff, today);
  final days = today - s.day; if (days <= 0) return s;
  final f = pow(.985, days).toDouble();
  return ReelSignals(s.clips, {for (final e in s.aff.entries) e.key: e.value <= -1.99 ? e.value : e.value * f}, today);
}

/// إشارات إضافية (من الإشارات التي أعلنتها TikTok): زيارة ملفها، فتح الفيديو كاملًا، إضافتها للمفضلة، و«غير مهتم».
const reelActionWeight = {'profile': .4, 'full': .7, 'follow': .9, 'nope': -.8};
ReelSignals recordAction(ReelSignals s, WorkGroup g, String action) {
  final w = reelActionWeight[action] ?? 0; final c = {...s.clips}; final a = {...s.aff};
  if (action == 'nope') c[g.key] = {...?c[g.key], 'h': 1};
  for (final k in _affKeys(g)) { a[k] = ((a[k] ?? 0) + w).clamp(-2.0, 2.0); }
  return ReelSignals(c, a, s.day);
}

/// حفظ/إلغاء حفظ (🔖). الحفظ إشارة إيجابية قوية.
ReelSignals toggleSave(ReelSignals s, WorkGroup g) {
  final c = {...s.clips}; final a = {...s.aff}; final m = {...?c[g.key]};
  final on = m['s'] != 1; if (on) { m['s'] = 1; m['st'] = _nowSec(); } else { m.remove('s'); }
  c[g.key] = m;
  if (on) { for (final k in _affKeys(g)) { a[k] = ((a[k] ?? 0) + .6).clamp(-2.0, 2.0); } }
  return ReelSignals(c, a, s.day);
}

/// مفاتيح المقاطع: «سجلّي» (الأحدث مشاهدة أولًا)، «المحفوظة»، «أعجبتني».
List<String> reelHistory(ReelSignals s) => (s.clips.entries.where((e) => (e.value['v'] ?? 0) > 0).toList()..sort((a, b) => (b.value['v'] ?? 0).compareTo(a.value['v'] ?? 0))).map((e) => e.key).toList();
List<String> reelSaved(ReelSignals s) => (s.clips.entries.where((e) => e.value['s'] == 1).toList()..sort((a, b) => (b.value['st'] ?? 0).compareTo(a.value['st'] ?? 0))).map((e) => e.key).toList();
List<String> reelLiked(ReelSignals s) => s.clips.entries.where((e) => e.value['l'] == 1).map((e) => e.key).toList();

/// تركيز الخلاصة (الضغط على اسم/وسم/استوديو في التعليق): pf = ممثلة، st = استوديو، tg = وسم.
bool reelFocusMatch(WorkGroup g, String kind, String v) => switch (kind) {
  'pf' => g.who.any((p) => p.id == v),
  'st' => norm(g.s) == norm(v),
  'tg' => g.tg.any((x) => norm(x) == norm(v)),
  _ => true,
};

Iterable<String> _affKeys(WorkGroup g) sync* { for (final p in g.who) { yield 'pf:${p.id}'; } if (g.s.trim().isNotEmpty) yield 'st:${norm(g.s)}'; }

/// تحديث بعد مشاهدة مقطع: [frac] نسبة ما شوهد (قد تتجاوز 1 عند الإعادة)، [like] إعجاب.
/// إكمال/إعادة/إعجاب ⇒ ميل إيجابي لممثلاته واستوديوه؛ تخطٍّ سريع (< 15٪) ⇒ ميل سلبي خفيف.
ReelSignals recordView(ReelSignals s, WorkGroup g, {required double frac, bool like = false}) {
  final c = {...s.clips}; final a = {...s.aff};
  final m = {...?c[g.key]};
  m['n'] = (m['n'] ?? 0) + 1; m['w'] = max((m['w'] ?? 0).toDouble(), frac); if (like) m['l'] = 1;
  if (frac > 0 || like) m['v'] = _nowSec();   // «سجلّي»
  c[g.key] = m;
  final sig = (frac >= 1.8 ? .7 : frac >= .9 ? .5 : frac >= .5 ? .2 : frac < .15 ? -.35 : 0.0) + (like ? .9 : 0);
  for (final k in _affKeys(g)) { a[k] = ((a[k] ?? 0) * .97 + sig).clamp(-2.0, 2.0); }
  return ReelSignals(c, a, s.day);
}

/// «أقل منها» / «أقل من هذا الاستوديو» / إخفاء المقطع.
ReelSignals dislike(ReelSignals s, {String? performerId, String? studio, String? hideKey}) {
  final a = {...s.aff}; final c = {...s.clips};
  if (performerId != null) a['pf:$performerId'] = -2;
  if (studio != null) a['st:${norm(studio)}'] = -2;
  if (hideKey != null) c[hideKey] = {...?c[hideKey], 'h': 1};
  return ReelSignals(c, a, s.day);
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
  final used = <String>{}; final out = <Reel>[]; final recent = <String>[]; final recentSt = <String>[];
  bool fitsP((WorkGroup, double, String) x) => !used.contains(x.$1.key) && !x.$1.who.any((p) => recent.contains(p.id));
  bool fits((WorkGroup, double, String) x) => fitsP(x) && (x.$1.s.trim().isEmpty || !recentSt.contains(norm(x.$1.s)));
  var i = 0, e = 0;
  while (out.length < n && (i < pool.length || e < explorePool.length)) {
    final exploreTurn = rnd.nextDouble() < .2 && e < explorePool.length;
    (WorkGroup, double, String)? pick;
    if (exploreTurn) { while (e < explorePool.length && pick == null) { final x = explorePool[e++]; if (fits(x)) pick = x; } }
    if (pick == null) {
      for (var k = i; k < pool.length; k++) { if (fits(pool[k])) { pick = pool[k]; if (k == i) i++; break; } }
      if (pick == null) { for (var k = i; k < pool.length; k++) { if (fitsP(pool[k])) { pick = pool[k]; if (k == i) i++; break; } } }
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
    if (pick.$1.s.trim().isNotEmpty) { recentSt.add(norm(pick.$1.s)); if (recentSt.length > 1) recentSt.removeAt(0); }
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


// ===================== جودة المقاطع (تُقاس عند التشغيل) =====================

/// مقطع «معاينة» لا إعلان: بلا صوت أو أقل من 480p.
bool isPreviewClip(Map? q) => q != null && (q['a'] == 0 || ((q['h'] as num?) ?? 9999) < 480);

/// خادم معظم مقاطعه معاينات (3 قياسات فأكثر و70٪ منها معاينات) ⇒ يُستبعد في وضع «إعلانات حقيقية فقط».
bool isPreviewHost(Map<String, dynamic> quality, String host) {
  var n = 0, bad = 0;
  quality.forEach((u, q) { if (hostOf(u) == host && q is Map) { n++; if (isPreviewClip(q)) bad++; } });
  return n >= 3 && bad / n >= .7;
}

/// هل يُعرض المقطع حسب الجودة المقاسة؟ (غير المقاس يُجرَّب)
bool qualityOk(Map<String, dynamic> quality, String url, {required bool hqOnly}) {
  if (!hqOnly) return true;
  if (isPreviewClip(quality[url] as Map?)) return false;
  return !isPreviewHost(quality, hostOf(url));
}
