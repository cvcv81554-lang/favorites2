import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/keys.dart';
import '../../../data/sources.dart';
import '../../../domain/age_gate.dart';
import '../../../domain/performer.dart';
import '../../../domain/sanitize.dart';
import '../../../domain/taste.dart';
import '../../core/state.dart';

/// توصية من تحليل الذوق (لها أسباب واختلافات حقيقية من البيانات).
class TasteRec {
  final String id, name, birth, country, image; final double score; final List<String> why, diff; final Map<String, Object> feats;
  const TasteRec(this.id, this.name, this.birth, this.country, this.image, this.score, this.why, this.diff, this.feats);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'birth': birth, 'country': country, 'image': image, 'score': score, 'why': why, 'diff': diff, 'f': feats};
  factory TasteRec.fromJson(Map j) => TasteRec('${j['id']}', '${j['name']}', '${j['birth'] ?? ''}', '${j['country'] ?? ''}', '${j['image'] ?? ''}', (j['score'] as num?)?.toDouble() ?? 0,
    [...(j['why'] as List? ?? const []).cast<String>()], [...(j['diff'] as List? ?? const []).cast<String>()], Map<String, Object>.from(j['f'] as Map? ?? const {}));
  int? get age => sdAge(birth).age;
}

class TasteState {
  final List<String> lines; final List<TasteRec> recs; final int analyzed, total, at; final String basis, msg, err; final bool busy, insufficient;
  const TasteState({this.lines = const [], this.recs = const [], this.analyzed = 0, this.total = 0, this.at = 0, this.basis = '', this.msg = '', this.err = '', this.busy = false, this.insufficient = false});
  TasteState copy({List<String>? lines, List<TasteRec>? recs, int? analyzed, int? total, int? at, String? basis, String? msg, String? err, bool? busy, bool? insufficient}) =>
    TasteState(lines: lines ?? this.lines, recs: recs ?? this.recs, analyzed: analyzed ?? this.analyzed, total: total ?? this.total, at: at ?? this.at, basis: basis ?? this.basis, msg: msg ?? this.msg, err: err ?? this.err, busy: busy ?? this.busy, insufficient: insufficient ?? this.insufficient);
}

class TasteN extends AsyncNotifier<TasteState> {
  @override
  Future<TasteState> build() async {
    final repo = await ref.watch(repoProvider.future);
    final j = await repo.kvGet('taste') as Map?;
    if (j == null) return const TasteState();
    return TasteState(lines: [...(j['lines'] as List? ?? const []).cast<String>()], recs: [for (final x in (j['recs'] as List? ?? const [])) TasteRec.fromJson(x as Map)],
      analyzed: (j['analyzed'] as num?)?.toInt() ?? 0, total: (j['total'] as num?)?.toInt() ?? 0, at: (j['at'] as num?)?.toInt() ?? 0, basis: '${j['basis'] ?? ''}', insufficient: j['insufficient'] == true);
  }
  TasteState get s => state.value ?? const TasteState();
  void _set(TasteState x) => state = AsyncData(x);

  /// التحليل الكامل: مفضلاتك ← بياناتهن الموثّقة (بذاكرة 14 يومًا) ← ملف الذوق ← بحث عن مشابهات ← ترتيب بأسباب.
  Future<void> analyze() async {
    if (s.busy) return;
    if (!await ApiKeys.has(ApiKeys.stash)) { _set(s.copy(err: 'تحليل الذوق يحتاج مفتاح StashDB — أضيفيه من «المزيد».')); return; }
    final repo = await ref.read(repoProvider.future);
    final lib = ref.read(libraryProvider).value ?? const <Performer>[];
    var basis = 'المفضلة';
    var pool = lib.where((p) => p.fav && !p.isMinor).toList();
    if (pool.where((p) => p.stashId.isNotEmpty).length < 3) { basis = 'المفضلة + الأعلى تقييمًا (المفضلة وحدها قليلة)'; pool = lib.where((p) => (p.fav || p.rating >= 4) && !p.isMinor).toList(); }
    final linked = pool.where((p) => p.stashId.isNotEmpty).toList();
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
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      await repo.kvSet('attr_cache', cache);
      final feats = [for (final p in linked) if (cache[p.stashId] is Map) featuresOf(Map<String, dynamic>.from((cache[p.stashId] as Map)['d'] as Map))];
      final prof = buildProfile(feats, total: pool.length);
      final lines = describeProfile(prof);
      if (!prof.sufficient) {
        final st = s.copy(busy: false, msg: '', lines: lines, recs: [], analyzed: prof.analyzed, total: pool.length, at: now, basis: basis, insufficient: true);
        _set(st); await _save(repo, st); return;
      }
      // 2) البحث عن مشابهات (StashDB الرسمي) حسب أوضح الخصائص + «عملن معهن»
      _set(s.copy(msg: 'البحث عن ممثلات مشابهات…', lines: lines));
      final strong = {for (final c in prof.strongCats) c.field: c.top.key};
      final filters = <String>[
        if (strong['ethnicity'] != null && strong['hair_color'] != null) 'ethnicity:${strong['ethnicity']},hair_color:{value:${strong['hair_color']},modifier:EQUALS}',
        if (strong['ethnicity'] != null && strong['country'] != null) 'ethnicity:${strong['ethnicity']},country:{value:"${strong['country']}",modifier:EQUALS}',
        if (strong['hair_color'] != null && strong['eye_color'] != null) 'hair_color:{value:${strong['hair_color']},modifier:EQUALS},eye_color:{value:${strong['eye_color']},modifier:EQUALS}',
        if (strong['ethnicity'] != null) 'ethnicity:${strong['ethnicity']}',
        if (strong.isEmpty && strong['country'] == null) '',
      ];
      final rnd = Random(DateTime.now().day + DateTime.now().month * 31);
      final found = <String, Map<String, dynamic>>{};
      const f = 'id name aliases gender birth_date country ethnicity hair_color eye_color height cup_size band_size waist_size hip_size breast_type career_start_year tattoos{location} piercings{location} scene_count images{url width height}';
      for (final flt in filters.take(4)) {
        final page = 1 + rnd.nextInt(3);   // صفحة متغيرة يوميًا ⇒ أسماء متجددة
        try {
          final d = await StashDB.q('query{queryPerformers(input:{gender:FEMALE${flt.isEmpty ? '' : ',$flt'},sort:POPULARITY,direction:DESC,per_page:40,page:$page}){performers{$f}}}');
          for (final x in ((d['queryPerformers'] as Map?)?['performers'] as List? ?? const [])) { if (x is Map) found['${x['id']}'] = Map<String, dynamic>.from(x); }
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final top = (linked.toList()..sort((a, b) => b.rating.compareTo(a.rating))).take(3);
      for (final p in top) {
        try {
          final d = await StashDB.q('query(\$id:ID!){queryPerformers(input:{performed_with:\$id,gender:FEMALE,sort:SHARED_SCENE_COUNT,direction:DESC,per_page:15}){performers{$f}}}', {'id': p.stashId});
          for (final x in ((d['queryPerformers'] as Map?)?['performers'] as List? ?? const [])) { if (x is Map) found['${x['id']}'] = Map<String, dynamic>.from(x)..['_with'] = p.name; }
        } on SourceError catch (e) { if (e.status == 401 || e.status == 403) rethrow; }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      // 3) الترتيب: البوابة أولًا، ثم استبعاد المكتبة والمخفيات والمتكرر، ثم التشابه + التعلّم
      final inLib = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId}, names = {for (final p in lib) norm(p.name)};
      final hidden = {...((await repo.kvGet('recs_hidden') as List?) ?? const []).cast<String>()};
      final fb = Map<String, double>.from((await repo.kvGet('taste_fb') as Map?)?.map((k, v) => MapEntry('$k', (v as num).toDouble())) ?? {});
      final imp = Map<String, dynamic>.from(await repo.kvGet('taste_imp') as Map? ?? {});
      final recs = <TasteRec>[];
      for (final x in found.values) {
        if (x['gender'] != null && x['gender'] != 'FEMALE') continue;
        if (!adultOk({'birth': x['birth_date']})) continue;                       // بوابة +18 قبل أي صورة
        final id = '${x['id']}';
        if (inLib.contains(id) || names.contains(norm(x['name'])) || hidden.contains(id)) continue;
        final seen = (imp[id] as num?)?.toInt() ?? 0;
        final ft = featuresOf(x);
        final sim = similarity(prof, ft, fb: fb);
        final score = sim.score - min(.3, seen * .07);                            // تقل كلما ظهرت لك دون تفاعل
        if (score < .3) continue;
        final why = [if (x['_with'] != null) 'عملت مع ${x['_with']} من مفضلاتك', ...sim.why];
        if (why.isEmpty) continue;                                               // لا اقتراح بلا سبب حقيقي
        final imgs = stashImages(x);
        recs.add(TasteRec(id, '${x['name']}', '${x['birth_date'] ?? ''}', '${x['country'] ?? ''}', imgs.isEmpty ? '' : imgs.first, score, why.take(4).toList(), sim.diff.take(2).toList(), ft));
      }
      recs.sort((a, b) => b.score.compareTo(a.score));
      // تنويع: حد لكل بلد في الصدارة
      final cnt = <String, int>{}; final out = <TasteRec>[];
      for (final r in recs) { final k = r.country; if ((cnt[k] = (cnt[k] ?? 0) + 1) > 4) continue; out.add(r); if (out.length >= 30) break; }
      final st = s.copy(busy: false, msg: '', lines: lines, recs: out, analyzed: prof.analyzed, total: pool.length, at: now, basis: basis, insufficient: false);
      _set(st); await _save(repo, st);
    } catch (e) { _set(s.copy(busy: false, msg: '', err: '$e')); }
  }

  Future<void> _save(dynamic repo, TasteState st) => repo.kvSet('taste', {'lines': st.lines, 'recs': [for (final r in st.recs) r.toJson()], 'analyzed': st.analyzed, 'total': st.total, 'at': st.at, 'basis': st.basis, 'insufficient': st.insufficient});

  /// ظهرت للمستخدم (تقل أولويتها إن تكررت بلا تفاعل).
  Future<void> seen(Iterable<String> ids) async {
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
}
final tasteProvider = AsyncNotifierProvider<TasteN, TasteState>(TasteN.new);
