import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../../domain/age_gate.dart';
import '../../../domain/performer.dart';
import '../../../domain/sanitize.dart';
import '../../../domain/taste.dart';
import '../../core/state.dart';

/// توصية من تحليل الذوق (لها أسباب واختلافات حقيقية من البيانات) + مساراتها في «اكتشف».
/// tags: top | with:<اسم> | debut | young | country | explore
class TasteRec {
  final String id, name, birth, country, image; final double score; final List<String> why, diff, tags; final Map<String, Object> feats;
  const TasteRec(this.id, this.name, this.birth, this.country, this.image, this.score, this.why, this.diff, this.feats, [this.tags = const []]);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'birth': birth, 'country': country, 'image': image, 'score': score, 'why': why, 'diff': diff, 'f': feats, 'tags': tags};
  factory TasteRec.fromJson(Map j) => TasteRec('${j['id']}', '${j['name']}', '${j['birth'] ?? ''}', '${j['country'] ?? ''}', '${j['image'] ?? ''}', (j['score'] as num?)?.toDouble() ?? 0,
    [...(j['why'] as List? ?? const []).cast<String>()], [...(j['diff'] as List? ?? const []).cast<String>()], Map<String, Object>.from(j['f'] as Map? ?? const {}), [...(j['tags'] as List? ?? const []).cast<String>()]);
  int? get age => sdAge(birth).age;
  int get pct => (40 + score * 58).round().clamp(40, 98);
}

/// شريط خاصية في ملف الذوق: اسم الحقل + أعلى القيم بنسبها.
class TraitBar {
  final String field, label; final List<(String, double)> items; final int n; final bool strong;
  const TraitBar(this.field, this.label, this.items, this.n, this.strong);
  Map<String, dynamic> toJson() => {'f': field, 'l': label, 'n': n, 's': strong, 'i': [for (final x in items) [x.$1, x.$2]]};
  factory TraitBar.fromJson(Map j) => TraitBar('${j['f']}', '${j['l']}', [for (final x in (j['i'] as List? ?? const [])) ('${(x as List)[0]}', (x[1] as num).toDouble())], (j['n'] as num?)?.toInt() ?? 0, j['s'] == true);
}

class TasteState {
  final List<String> lines; final List<TraitBar> bars; final List<TasteRec> recs; final int analyzed, total, at, unlinked; final String basis, msg, err; final bool busy, insufficient;
  final Set<String> ignore; final List<(String, String)> withNames;   // (stashId، الاسم) للمفضلات التي صُنعت منها مسارات «عملن معها»
  const TasteState({this.lines = const [], this.bars = const [], this.recs = const [], this.analyzed = 0, this.total = 0, this.at = 0, this.unlinked = 0, this.basis = '', this.msg = '', this.err = '', this.busy = false, this.insufficient = false, this.ignore = const {}, this.withNames = const []});
  TasteState copy({List<String>? lines, List<TraitBar>? bars, List<TasteRec>? recs, int? analyzed, int? total, int? at, int? unlinked, String? basis, String? msg, String? err, bool? busy, bool? insufficient, Set<String>? ignore, List<(String, String)>? withNames}) =>
    TasteState(lines: lines ?? this.lines, bars: bars ?? this.bars, recs: recs ?? this.recs, analyzed: analyzed ?? this.analyzed, total: total ?? this.total, at: at ?? this.at, unlinked: unlinked ?? this.unlinked, basis: basis ?? this.basis,
      msg: msg ?? this.msg, err: err ?? this.err, busy: busy ?? this.busy, insufficient: insufficient ?? this.insufficient, ignore: ignore ?? this.ignore, withNames: withNames ?? this.withNames);
}

const _tasteF = 'id name aliases gender birth_date country ethnicity hair_color eye_color height cup_size band_size waist_size hip_size breast_type career_start_year career_end_year tattoos{location} piercings{location} scene_count images{url width height}';

class TasteN extends AsyncNotifier<TasteState> {
  @override
  Future<TasteState> build() async {
    final repo = await ref.watch(repoProvider.future);
    if (kIsWeb && Uri.base.queryParameters['demo'] == '1') return _demo();
    final ig = {...((await repo.kvGet('taste_ignore') as List?) ?? const []).cast<String>()};
    final j = await repo.kvGet('taste') as Map?;
    if (j == null) return TasteState(ignore: ig);
    return TasteState(lines: [...(j['lines'] as List? ?? const []).cast<String>()], bars: [for (final x in (j['bars'] as List? ?? const [])) TraitBar.fromJson(x as Map)],
      recs: [for (final x in (j['recs'] as List? ?? const [])) TasteRec.fromJson(x as Map)],
      analyzed: (j['analyzed'] as num?)?.toInt() ?? 0, total: (j['total'] as num?)?.toInt() ?? 0, at: (j['at'] as num?)?.toInt() ?? 0, unlinked: (j['unlinked'] as num?)?.toInt() ?? 0,
      basis: '${j['basis'] ?? ''}', insufficient: j['insufficient'] == true, ignore: ig,
      withNames: [for (final x in (j['with'] as List? ?? const [])) ('${(x as List)[0]}', '${x[1]}')]);
  }
  TasteState get s => state.value ?? const TasteState();
  void _set(TasteState x) => state = AsyncData(x);

  /// تبديل حقل في التحليل (يُطبَّق عند «حدّث»).
  Future<void> toggleField(String f) async {
    final ig = {...s.ignore}; if (!ig.remove(f)) ig.add(f);
    await (await ref.read(repoProvider.future)).kvSet('taste_ignore', ig.toList());
    _set(s.copy(ignore: ig));
  }

  /// التحليل الكامل: مفضلاتك (موزونة بتقييمك) ← بياناتهن الموثّقة (ذاكرة 14 يومًا) ← ملف الذوق ← مرشحات من عدة مصادر رسمية ← ترتيب بأسباب ← مسارات.
  Future<void> analyze() async {
    if (s.busy) return;
    if (!await ApiKeys.has(ApiKeys.stash)) { _set(s.copy(err: 'تحليل الذوق يحتاج مفتاح StashDB — أضيفيه من «المزيد».')); return; }
    final repo = await ref.read(repoProvider.future);
    final lib = ref.read(libraryProvider).value ?? const <Performer>[];
    var basis = 'المفضلة';
    var pool = lib.where((p) => p.fav && !p.isMinor).toList();
    if (pool.where((p) => p.stashId.isNotEmpty).length < 3) { basis = 'المفضلة + الأعلى تقييمًا (المفضلة وحدها قليلة)'; pool = lib.where((p) => (p.fav || p.rating >= 4) && !p.isMinor).toList(); }
    final linked = pool.where((p) => p.stashId.isNotEmpty).toList();
    final unlinked = pool.length - linked.length;
    _set(s.copy(busy: true, err: '', msg: 'جمع بيانات ${linked.length} ممثلة…'));
    try {
      // 1) بيانات موثّقة مع ذاكرة
      final cache = Map<String, dynamic>.from(await repo.kvGet('attr_cache') as Map? ?? {});
      final now = DateTime.now().millisecondsSinceEpoch; var i = 0;
      for (final p in linked) {
        i++;
        final c = cache[p.stashId];
        if (c is Map && now - ((c['t'] as num?) ?? 0) < 14 * 86400000) continue;
        _set(s.copy(msg: 'بيانات ${p.name} ($i/${linked.length})'));
        try { final d = await stashPerformer(p.stashId); if (d != null) cache[p.stashId] = {'t': now, 'd': d}; }
        on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await repo.kvSet('attr_cache', cache);
      final have = [for (final p in linked) if (cache[p.stashId] is Map) p];
      final feats = [for (final p in have) featuresOf(Map<String, dynamic>.from((cache[p.stashId] as Map)['d'] as Map))];
      final weights = [for (final p in have) tasteWeight(fav: p.fav, rating: p.rating.toDouble())];
      final prof = buildProfile(feats, total: pool.length, weights: weights, ignore: s.ignore);
      final lines = describeProfile(prof);
      final bars = [for (final c in (prof.cats.values.where((c) => c.n >= 2).toList()..sort((a, b) => b.share.compareTo(a.share))))
        TraitBar(c.field, fieldNames[c.field] ?? c.field, [for (final x in c.topN(3)) (attrLabel(c.field, x.$1), x.$2)], c.n, c.strong)];
      if (!prof.sufficient) {
        final st = s.copy(busy: false, msg: '', lines: lines, bars: bars, recs: [], analyzed: prof.analyzed, total: pool.length, unlinked: unlinked, at: now, basis: basis, insufficient: true, withNames: []);
        _set(st); await _save(repo, st); return;
      }
      // 2) مرشحات من StashDB الرسمي: أوضح الخصائص (صفحات متغيرة يوميًا) + وجوه جديدة + 18–21 + بلدك + «عملن معها»
      _set(s.copy(msg: 'البحث عن ممثلات يشبهن ذوقك…', lines: lines, bars: bars));
      final strong = {for (final c in prof.strongCats) c.field: c.top.key};
      String eq(String f) => '$f:{value:${strong[f]},modifier:EQUALS}';
      final eth = strong['ethnicity'] != null ? 'ethnicity:${strong['ethnicity']}' : null;
      final hair = strong['hair_color'] != null ? eq('hair_color') : null;
      final eyes = strong['eye_color'] != null ? eq('eye_color') : null;
      final cc = strong['country'];
      final rnd = Random(DateTime.now().year * 400 + DateTime.now().month * 32 + DateTime.now().day);
      final yr = DateTime.now().year;
      final queries = <(String, String, String)>[   // (المرشح، الترتيب، الوسم)
        if (eth != null && hair != null) ('$eth,$hair', 'POPULARITY', 'top'),
        if (hair != null && eyes != null) ('$hair,$eyes', 'POPULARITY', 'top'),
        if (eth != null) (eth, 'POPULARITY', 'top'),
        if (eth == null && hair == null) ('', 'POPULARITY', 'top'),
        ([?eth, 'career_start_year:{value:${yr - 3},modifier:GREATER_THAN}'].join(','), 'DEBUT', 'debut'),
        ([?eth, 'age:{value:22,modifier:LESS_THAN}'].join(','), 'POPULARITY', 'young'),
        if (cc != null) ('country:{value:"$cc",modifier:EQUALS}', 'POPULARITY', 'country'),
      ];
      final found = <String, Map<String, dynamic>>{}; final tagsOf = <String, Set<String>>{};
      var qi = 0;
      for (final (flt, sort, tag) in queries) {
        qi++; _set(s.copy(msg: 'البحث عن مشابهات ($qi/${queries.length + 5})…'));
        final page = tag == 'top' ? 1 + rnd.nextInt(3) : 1;   // صفحة متغيرة يوميًا ⇒ أسماء متجددة
        try {
          final d = await StashDB.q('query{queryPerformers(input:{gender:FEMALE${flt.isEmpty ? '' : ',$flt'},sort:$sort,direction:DESC,per_page:40,page:$page}){performers{$_tasteF}}}');
          for (final x in ((d['queryPerformers'] as Map?)?['performers'] as List? ?? const [])) {
            if (x is! Map) continue; final id = '${x['id']}';
            found[id] ??= Map<String, dynamic>.from(x); (tagsOf[id] ??= {}).add(tag);
          }
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      final top = (have.toList()..sort((a, b) => (b.rating + (b.fav ? 1 : 0)).compareTo(a.rating + (a.fav ? 1 : 0)))).take(5).toList();
      final withNames = <(String, String)>[];
      for (final p in top) {
        qi++; _set(s.copy(msg: 'من عمل مع ${p.name}… ($qi/${queries.length + 5})'));
        try {
          final d = await StashDB.q('query(\$id:ID!){queryPerformers(input:{performed_with:\$id,gender:FEMALE,sort:SHARED_SCENE_COUNT,direction:DESC,per_page:20}){performers{$_tasteF}}}', {'id': p.stashId});
          var got = 0;
          for (final x in ((d['queryPerformers'] as Map?)?['performers'] as List? ?? const [])) {
            if (x is! Map) continue; final id = '${x['id']}';
            found[id] ??= Map<String, dynamic>.from(x); (tagsOf[id] ??= {}).add('with:${p.stashId}'); got++;
          }
          if (got > 0) withNames.add((p.stashId, p.name));
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      final names = {for (final p in have) p.stashId: p.name};
      // 3) الترتيب: البوابة أولًا، ثم استبعاد المكتبة والمخفيات، ثم التشابه + التعلّم + التجدد
      final inLib = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId}, libNames = {for (final p in lib) norm(p.name)};
      final hidden = {...((await repo.kvGet('recs_hidden') as List?) ?? const []).cast<String>()};
      final fb = Map<String, double>.from((await repo.kvGet('taste_fb') as Map?)?.map((k, v) => MapEntry('$k', (v as num).toDouble())) ?? {});
      final imp = Map<String, dynamic>.from(await repo.kvGet('taste_imp') as Map? ?? {});
      final recs = <TasteRec>[];
      for (final x in found.values) {
        if (x['gender'] != null && x['gender'] != 'FEMALE') continue;
        if (!adultOk({'birth': x['birth_date']})) continue;                       // بوابة +18 قبل أي صورة
        final id = '${x['id']}';
        if (inLib.contains(id) || libNames.contains(norm(x['name'])) || hidden.contains(id)) continue;
        final seen = (imp[id] as num?)?.toInt() ?? 0;
        final ft = featuresOf(x);
        final sim = similarity(prof, ft, fb: fb);
        final tags = {...?tagsOf[id]};
        final withs = [for (final t in tags) if (t.startsWith('with:')) names[t.substring(5)]].whereType<String>().toList();
        var score = sim.score - min(.3, seen * .06) + (withs.isNotEmpty ? .06 : 0);   // تقل كلما ظهرت دون تفاعل
        score = score.clamp(0.0, 1.0);
        if (score < .3) continue;
        final why = [if (withs.isNotEmpty) 'عملت مع ${withs.take(2).join(' و')} من مفضلاتك', ...sim.why];
        if (why.isEmpty) continue;                                               // لا اقتراح بلا سبب حقيقي
        final a = sdAge(x['birth_date']).age;
        if (a != null && a <= 21 && '${x['birth_date'] ?? ''}'.length >= 10) { tags.add('young'); } else { tags.remove('young'); }   // 18–21 بتاريخ كامل فقط
        if (score >= .45 && score < .68 && sim.diff.isNotEmpty) tags.add('explore');
        final imgs = stashImages(x);
        recs.add(TasteRec(id, '${x['name']}', '${x['birth_date'] ?? ''}', '${x['country'] ?? ''}', imgs.isEmpty ? '' : imgs.first, score, why.take(4).toList(), sim.diff.take(2).toList(), ft, tags.toList()));
      }
      recs.sort((a, b) => b.score.compareTo(a.score));
      final st = s.copy(busy: false, msg: '', lines: lines, bars: bars, recs: recs.take(120).toList(), analyzed: prof.analyzed, total: pool.length, unlinked: unlinked, at: now, basis: basis, insufficient: false, withNames: withNames);
      _set(st); await _save(repo, st);
    } catch (e) { _set(s.copy(busy: false, msg: '', err: '$e')); }
  }

  Future<void> _save(dynamic repo, TasteState st) => repo.kvSet('taste', {'lines': st.lines, 'bars': [for (final b in st.bars) b.toJson()], 'recs': [for (final r in st.recs) r.toJson()], 'analyzed': st.analyzed, 'total': st.total,
    'unlinked': st.unlinked, 'at': st.at, 'basis': st.basis, 'insufficient': st.insufficient, 'with': [for (final w in st.withNames) [w.$1, w.$2]]});

  /// ظهرت للمستخدم (تقل أولويتها إن تكررت بلا تفاعل).
  Future<void> seen(Iterable<String> ids) async {
    if (kIsWeb && Uri.base.queryParameters['demo'] == '1') return;
    final repo = await ref.read(repoProvider.future);
    final imp = Map<String, dynamic>.from(await repo.kvGet('taste_imp') as Map? ?? {});
    for (final id in ids) { imp[id] = ((imp[id] as num?)?.toInt() ?? 0) + 1; }
    await repo.kvSet('taste_imp', imp);
  }

  /// تعلّم: أضافت (+) أو «ليست ذوقي» (−) — يُعدّل أوزان الخصائص، وتُزال من القائمة الحالية.
  Future<void> feedback(String id, double delta) async {
    final repo = await ref.read(repoProvider.future);
    final r = s.recs.where((x) => x.id == id).firstOrNull;
    if (r != null) {
      final fb = Map<String, double>.from((await repo.kvGet('taste_fb') as Map?)?.map((k, v) => MapEntry('$k', (v as num).toDouble())) ?? {});
      await repo.kvSet('taste_fb', learn(fb, r.feats, delta));
    }
    final st = s.copy(recs: s.recs.where((x) => x.id != id).toList()); _set(st); await _save(repo, st);
  }

  /// بيانات تجريبية محايدة لنسخة الويب (?demo=1) فقط — لا تُعرض كنتائج حقيقية.
  static TasteState _demo() {
    final r = Random(7);
    final recs = [for (var i = 0; i < 40; i++) TasteRec('demo-c$i', 'مرشحة ${i + 1}', '${1994 + i % 10}-0${1 + i % 9}-1${i % 9}', ['CZ', 'US', 'HU', 'RU'][i % 4], 'https://img.test/p${i % 12}.png',
      .95 - i * .015, ['لون الشعر بني مثل 75٪ من مفضلاتك', if (i % 3 == 0) 'عملت مع نموذج 1 من مفضلاتك', 'طولها ${160 + r.nextInt(10)} سم قريب من متوسط مفضلاتك'], [if (i % 4 == 1) 'العرق لاتينية (أغلب مفضلاتك قوقازية)'], const {},
      ['top', if (i % 3 == 0) 'with:demo', if (i % 5 == 0) 'debut', if (i % 6 == 0) 'young', if (i % 4 == 0) 'country', if (i % 4 == 1) 'explore'])];
    return TasteState(at: DateTime.now().millisecondsSinceEpoch, analyzed: 12, total: 14, unlinked: 2, basis: 'المفضلة', recs: recs, withNames: const [('demo', 'نموذج 1')],
      lines: const ['لون الشعر: بني (75٪ من 12)', 'العرق: قوقازية (67٪ من 12)', 'الطول: متوسط 165 سم (155–172، من 12)'],
      bars: const [TraitBar('hair_color', 'لون الشعر', [('بني', .75), ('أشقر', .17), ('أسود', .08)], 12, true), TraitBar('ethnicity', 'العرق', [('قوقازية', .67), ('لاتينية', .25), ('مختلطة', .08)], 12, true),
        TraitBar('eye_color', 'لون العيون', [('بنية', .5), ('زرقاء', .33), ('خضراء', .17)], 12, true), TraitBar('tattoos', 'الوشوم', [('بلا وشوم', .58), ('لديها وشوم', .42)], 12, true)]);
  }
}
final tasteProvider = AsyncNotifierProvider<TasteN, TasteState>(TasteN.new);
