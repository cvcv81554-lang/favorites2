import 'dart:math';

import 'age_gate.dart';
import 'performer.dart';
import 'sanitize.dart';

/// مرشحة اقتراح (من StashDB الرسمي) مع أسباب الاقتراح — لا شيء مُخمَّن، كل سبب له مصدر.
class RecCand {
  final String id, name, birth, country, image;
  final int? careerStart, scenes;
  final Set<String> withSeeds; // ممثلات من مكتبتك عملت معهن (مصدر: performed_with)
  final Set<String> lanes;     // debut | country
  double score = 0;
  List<String> reasons = [];
  RecCand({required this.id, required this.name, this.birth = '', this.country = '', this.image = '', this.careerStart, this.scenes, Set<String>? withSeeds, Set<String>? lanes})
      : withSeeds = withSeeds ?? {}, lanes = lanes ?? {};

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'birth': birth, 'country': country, 'image': image, 'cs': careerStart, 'sc': scenes, 'w': withSeeds.toList(), 'l': lanes.toList()};
  factory RecCand.fromJson(Map<String, dynamic> j) => RecCand(id: '${j['id']}', name: '${j['name']}', birth: '${j['birth'] ?? ''}', country: '${j['country'] ?? ''}', image: '${j['image'] ?? ''}',
      careerStart: (j['cs'] as num?)?.toInt(), scenes: (j['sc'] as num?)?.toInt(), withSeeds: {...((j['w'] as List?) ?? const []).cast<String>()}, lanes: {...((j['l'] as List?) ?? const []).cast<String>()});

  /// بوابة +18: بلا تاريخ أو تاريخ يؤكد 18+.
  bool get adult => adultOk({'birth': birth});
  int? get age => sdAge(birth).age;
  /// 18–21 «موثّقة»: تاريخ كامل YYYY-MM-DD صالح من المصدر، والعمر بين 18 و21 اليوم.
  bool get young18to21 {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(birth)) return false;
    final a = sdAge(birth); return !a.invalid && a.age != null && a.age! >= 18 && a.age! <= 21;
  }
}

/// وزن ممثلة من مكتبتك كبذرة للاقتراح: التقييم + المفضلة + التصفح.
double seedWeight(Performer p) => (p.rating / 5) + (p.fav ? .6 : 0) + min(.4, p.views * .05) + (p.tier == 'S' ? .3 : p.tier == 'A' ? .15 : 0);

/// يرتّب المرشحات ويكتب أسبابًا مفهومة. [lib] مكتبتك (بعد البوابة)، [hidden] من أخفيتها.
List<RecCand> rankRecs(List<RecCand> pool, List<Performer> lib, {Set<String> hidden = const {}}) {
  final inLib = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId};
  final names = {for (final p in lib) norm(p.name)};
  final seedW = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId: seedWeight(p)};
  final seedName = {for (final p in lib) if (p.stashId.isNotEmpty) p.stashId: p.name};
  final cc = <String, int>{}; for (final p in lib) { if (p.country.isNotEmpty) cc[p.country.toUpperCase()] = (cc[p.country.toUpperCase()] ?? 0) + 1; }
  final ccTotal = max(1, cc.values.fold<int>(0, (a, b) => a + b));
  final ages = [for (final p in lib) if (p.age != null) p.age!]..sort();
  final medAge = ages.isEmpty ? null : ages[ages.length ~/ 2];
  final out = <RecCand>[];
  for (final c in pool) {
    if (!c.adult || inLib.contains(c.id) || names.contains(norm(c.name)) || hidden.contains(c.id)) continue;
    final ws = c.withSeeds.where(seedW.containsKey).toList()..sort((a, b) => seedW[b]!.compareTo(seedW[a]!));
    final co = ws.fold<double>(0, (s, id) => s + seedW[id]!);
    final ccShare = c.country.isEmpty ? 0.0 : (cc[c.country.toUpperCase()] ?? 0) / ccTotal;
    final ageFit = (medAge == null || c.age == null) ? 0.0 : max(0.0, 1 - (c.age! - medAge).abs() / 10);
    final pop = c.scenes == null ? 0.0 : min(1.0, log(1 + c.scenes!) / log(400));
    c.score = .55 * min(1.0, co / 2.5) + .2 * ccShare + .12 * ageFit + .13 * pop;
    c.reasons = [
      if (ws.isNotEmpty) 'عملت مع ${ws.take(2).map((id) => seedName[id]).join(' و')}${ws.length > 2 ? ' و${ws.length - 2} أخريات' : ''} من مكتبتك',
      if (ccShare >= .15) 'من ${c.country} مثل ${cc[c.country.toUpperCase()]} من مكتبتك',
      if (c.lanes.contains('debut') && c.careerStart != null) 'بدأت مسيرتها ${c.careerStart}',
      if (ageFit > .7) 'قريبة من الفئة العمرية التي تفضّلها',
    ];
    out.add(c);
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// اختيار ثابت طوال اليوم (نفس البذرة ⇒ نفس الاختيار)، بحد للبلد الواحد كي يتنوّع.
List<RecCand> dailyPick(List<RecCand> ranked, {int n = 8, int perCountry = 2, DateTime? day}) {
  final d = day ?? DateTime.now();
  final rnd = Random(d.year * 10000 + d.month * 100 + d.day);
  final top = ranked.take(max(n * 3, 24)).toList()..shuffle(rnd);
  final cnt = <String, int>{}; final out = <RecCand>[];
  for (final c in top) {
    final k = c.country.isEmpty ? '?' : c.country;
    if ((cnt[k] ?? 0) >= perCountry) continue;
    cnt[k] = (cnt[k] ?? 0) + 1; out.add(c);
    if (out.length >= n) break;
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}
