import 'dart:math';

import 'age_gate.dart';

/// تحليل الذوق — **من البيانات المهنية الموثّقة فقط** (حقول StashDB الوصفية)، بلا أي تحليل للصور أو الوجوه.
/// كل نتيجة لها مصدر: عدد المفضلات التي تملك الحقل، والنسبة.

const _labels = <String, Map<String, String>>{
  'ethnicity': {'CAUCASIAN': 'قوقازية', 'BLACK': 'سمراء البشرة', 'ASIAN': 'آسيوية', 'INDIAN': 'هندية', 'LATIN': 'لاتينية', 'MIDDLE_EASTERN': 'شرق أوسطية', 'MIXED': 'مختلطة', 'OTHER': 'أخرى'},
  'hair_color': {'BLONDE': 'أشقر', 'BRUNETTE': 'بني', 'BLACK': 'أسود', 'RED': 'أحمر', 'AUBURN': 'كستنائي', 'GREY': 'رمادي', 'BALD': 'بلا شعر', 'VARIOUS': 'متنوع', 'WHITE': 'أبيض', 'OTHER': 'آخر'},
  'eye_color': {'BLUE': 'زرقاء', 'BROWN': 'بنية', 'GREY': 'رمادية', 'GREEN': 'خضراء', 'HAZEL': 'عسلية', 'RED': 'حمراء'},
  'breast_type': {'NATURAL': 'طبيعي', 'FAKE': 'مُعزَّز', 'NA': 'غير محدد'},
  'tattoos': {'yes': 'لديها وشوم', 'no': 'بلا وشوم'},
  'piercings': {'yes': 'لديها ثقوب', 'no': 'بلا ثقوب'},
  'active': {'yes': 'ما زالت نشطة', 'no': 'اعتزلت'},
};
const fieldNames = {'active': 'النشاط', 'ethnicity': 'العرق', 'hair_color': 'لون الشعر', 'eye_color': 'لون العيون', 'breast_type': 'الصدر', 'country': 'البلد', 'tattoos': 'الوشوم', 'piercings': 'الثقوب',
  'height': 'الطول', 'age': 'العمر', 'career_start_year': 'بداية المسيرة', 'cup': 'مقاس الصدر', 'waist_size': 'الخصر', 'hip_size': 'الأرداف'};
String attrLabel(String field, String value) => _labels[field]?[value] ?? value;

/// تحويل سجل StashDB إلى خصائص قابلة للمقارنة (الحقول الغائبة لا تُخمَّن).
Map<String, Object> featuresOf(Map<String, dynamic> p) {
  final f = <String, Object>{};
  for (final k in ['ethnicity', 'hair_color', 'eye_color', 'breast_type']) { final v = p[k]; if (v is String && v.isNotEmpty && v != 'NA' && v != 'OTHER') f[k] = v; }
  final c = '${p['country'] ?? ''}'.trim().toUpperCase(); if (c.isNotEmpty) f['country'] = c;
  if (p['tattoos'] is List) f['tattoos'] = (p['tattoos'] as List).isEmpty ? 'no' : 'yes';
  if (p['piercings'] is List) f['piercings'] = (p['piercings'] as List).isEmpty ? 'no' : 'yes';
  if (p['career_start_year'] is num) f['active'] = p['career_end_year'] is num ? 'no' : 'yes';
  for (final k in ['height', 'career_start_year', 'waist_size', 'hip_size']) { final v = p[k]; if (v is num && v > 0) f[k] = v.toDouble(); }
  final a = sdAge(p['birth_date']); if (a.age != null && a.age! >= 18) f['age'] = a.age!.toDouble();
  final cup = '${p['cup_size'] ?? ''}'.trim().toUpperCase();
  if (RegExp(r'^[A-K]').hasMatch(cup)) f['cup'] = (cup.codeUnitAt(0) - 64 + (cup.length > 1 && cup[1] == cup[0] ? .5 : 0)).toDouble();
  return f;
}

/// [counts] أوزان (المفضلة الأعلى تقييمًا تزن أكثر)، [n] عدد المفضلات التي تملك الحقل، [wsum] مجموع الأوزان.
class CatStat { final String field; final Map<String, double> counts; final int n; final double wsum; const CatStat(this.field, this.counts, this.n, this.wsum);
  MapEntry<String, double> get top => counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  double get share => wsum == 0 ? 0 : top.value / wsum;
  double shareOf(String v) => wsum == 0 ? 0 : (counts[v] ?? 0) / wsum;
  /// أعلى القيم بنسبها (للأشرطة في الواجهة).
  List<(String, double)> topN(int k) => [for (final e in (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(k)) (e.key, e.value / wsum)];
  /// تفضيل واضح: 3 مفضلات على الأقل تملك الحقل، والقيمة الأولى ≥ 50٪.
  bool get strong => n >= 3 && share >= .5;
}
class NumStat { final String field; final double mean, sd, lo, hi; final int n; const NumStat(this.field, this.mean, this.sd, this.lo, this.hi, this.n); }

class TasteProfile {
  final int total, analyzed; final Map<String, CatStat> cats; final Map<String, NumStat> nums;
  const TasteProfile(this.total, this.analyzed, this.cats, this.nums);
  /// يكفي للتحليل: 3 مفضلات على الأقل لها بيانات موثّقة.
  bool get sufficient => analyzed >= 3;
  List<CatStat> get strongCats => (cats.values.where((c) => c.strong).toList()..sort((a, b) => b.share.compareTo(a.share)));
}

const catFields = ['ethnicity', 'hair_color', 'eye_color', 'breast_type', 'country', 'tattoos', 'piercings', 'active'];
const numFields = ['height', 'age', 'career_start_year', 'cup', 'waist_size', 'hip_size'];

/// [weights]: وزن كل مفضلة (افتراضي 1). [ignore]: حقول اختارت المستخدمة ألّا تُحسب.
TasteProfile buildProfile(List<Map<String, Object>> feats, {int? total, List<double>? weights, Set<String> ignore = const {}}) {
  final cats = <String, CatStat>{}, nums = <String, NumStat>{};
  double wt(int i) => weights != null && i < weights.length ? weights[i] : 1.0;
  for (final k in catFields) {
    if (ignore.contains(k)) continue;
    final c = <String, double>{}; var n = 0; var ws = 0.0;
    for (var i = 0; i < feats.length; i++) { final v = feats[i][k]; if (v is String) { c[v] = (c[v] ?? 0) + wt(i); n++; ws += wt(i); } }
    if (n > 0) cats[k] = CatStat(k, c, n, ws);
  }
  for (final k in numFields) {
    if (ignore.contains(k)) continue;
    final v = <double>[], w = <double>[];
    for (var i = 0; i < feats.length; i++) { final x = feats[i][k]; if (x is double) { v.add(x); w.add(wt(i)); } }
    if (v.length < 2) continue;
    final ws = w.reduce((a, b) => a + b);
    var m = 0.0; for (var i = 0; i < v.length; i++) { m += v[i] * w[i]; } m /= ws;
    var vv = 0.0; for (var i = 0; i < v.length; i++) { vv += w[i] * (v[i] - m) * (v[i] - m); }
    nums[k] = NumStat(k, m, sqrt(vv / ws), v.reduce(min), v.reduce(max), v.length);
  }
  return TasteProfile(total ?? feats.length, feats.where((f) => f.isNotEmpty).length, cats, nums);
}

/// ملخص مقروء للتحليل (كل سطر بنسبته وعدده — لا شيء مخترع).
List<String> describeProfile(TasteProfile p) {
  final out = <String>[];
  for (final c in p.strongCats.take(7)) { out.add('${fieldNames[c.field]}: ${attrLabel(c.field, c.top.key)} (${(c.share * 100).round()}٪ من ${c.n})'); }
  String r(double x) => x.toStringAsFixed(0);
  final h = p.nums['height']; if (h != null) out.add('الطول: متوسط ${r(h.mean)} سم (${r(h.lo)}–${r(h.hi)}، من ${h.n})');
  final a = p.nums['age']; if (a != null) out.add('العمر: متوسط ${r(a.mean)} سنة (${r(a.lo)}–${r(a.hi)})');
  final cs = p.nums['career_start_year']; if (cs != null) out.add('بداية المسيرة: حوالي ${r(cs.mean)} (${r(cs.lo)}–${r(cs.hi)})');
  // تنوع: حقول بلا قيمة غالبة
  final mixed = p.cats.values.where((c) => c.n >= 3 && !c.strong).map((c) => fieldNames[c.field]).toList();
  if (mixed.isNotEmpty) out.add('متنوع لديك: ${mixed.join('، ')}');
  return out;
}

/// تعلّم من التفاعل: أوزان لقيم الخصائص (+ عند الإضافة، − عند «ليست ذوقي»)، محدودة بين −1 و+1.
Map<String, double> learn(Map<String, double> w, Map<String, Object> feats, double delta) {
  final o = Map<String, double>.from(w);
  feats.forEach((k, v) { if (v is String) { final key = '$k=$v'; o[key] = ((o[key] ?? 0) + delta).clamp(-1.0, 1.0); } });
  return o;
}

/// تشابه مرشحة مع الذوق: درجة 0..1 + أسباب التشابه + أوجه الاختلاف.
({double score, List<String> why, List<String> diff}) similarity(TasteProfile p, Map<String, Object> f, {Map<String, double> fb = const {}}) {
  var got = 0.0, total = 0.0; final why = <String>[], diff = <String>[];
  const w = {'ethnicity': 1.2, 'hair_color': 1.0, 'eye_color': .5, 'breast_type': .8, 'country': .6, 'tattoos': .5, 'piercings': .3, 'active': .3};
  for (final e in p.cats.entries) {
    final v = f[e.key]; if (v is! String || e.value.n < 2) continue;
    final weight = (w[e.key] ?? .5) * (e.value.strong ? 1.0 : .5);
    total += weight;
    final share = e.value.shareOf(v);
    got += weight * share;
    if (e.value.strong && v == e.value.top.key) { why.add('${fieldNames[e.key]} ${attrLabel(e.key, v)} مثل ${(e.value.share * 100).round()}٪ من مفضلاتك'); }
    else if (e.value.strong && share == 0) { diff.add('${fieldNames[e.key]} ${attrLabel(e.key, v)} (أغلب مفضلاتك ${attrLabel(e.key, e.value.top.key)})'); }
  }
  const nw = {'height': .8, 'age': .7, 'career_start_year': .4, 'cup': .6, 'waist_size': .3, 'hip_size': .3};
  for (final e in p.nums.entries) {
    final v = f[e.key]; if (v is! double) continue;
    final weight = nw[e.key] ?? .3; total += weight;
    final sd = max(e.value.sd, e.key == 'height' ? 4.0 : e.key == 'age' ? 3.0 : 2.0);
    final z = (v - e.value.mean).abs() / sd;
    final m = exp(-z * z / 2); got += weight * m;
    if (m > .75 && e.key == 'height') why.add('طولها ${v.toStringAsFixed(0)} سم قريب من متوسط مفضلاتك');
    if (m > .75 && e.key == 'age') why.add('عمرها ${v.toStringAsFixed(0)} ضمن الفئة التي تفضّلها');
  }
  var score = total == 0 ? 0.0 : got / total;
  // التعلّم من تفاعلاتك
  var adj = 0.0; f.forEach((k, v) { if (v is String) adj += fb['$k=$v'] ?? 0; });
  score = (score + adj * .08).clamp(0.0, 1.0);
  return (score: score, why: why, diff: diff);
}

/// وزن مفضلة في التحليل: المفضلة ★ أساس، والتقييم الأعلى يزيد الوزن (0.6..2).
double tasteWeight({required bool fav, required double rating}) => ((fav ? 1.0 : .7) + (rating > 0 ? (rating - 3) * .25 : 0)).clamp(.6, 2.0);
