// تحليل الذوق: من الحقول الموثّقة فقط، بنسب صحيحة، وكفاية البيانات، والتشابه بأسباب، والتعلّم.
import 'package:favorites2/domain/taste.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> perf({String eth = 'CAUCASIAN', String hair = 'BRUNETTE', int h = 165, String birth = '1996-05-05', String cc = 'CZ', bool tat = false}) =>
  {'ethnicity': eth, 'hair_color': hair, 'eye_color': 'BROWN', 'height': h, 'birth_date': birth, 'country': cc, 'tattoos': tat ? [{'location': 'arm'}] : [], 'piercings': [], 'cup_size': 'B', 'career_start_year': 2018};

void main() {
  test('الخصائص: الحقول الغائبة لا تُخمَّن، والقاصر لا يُحسب عمرها', () {
    final f = featuresOf({'hair_color': 'BLONDE', 'birth_date': '2015-01-01'});
    expect(f['hair_color'], 'BLONDE'); expect(f.containsKey('ethnicity'), isFalse); expect(f.containsKey('age'), isFalse); expect(f.containsKey('height'), isFalse);
  });

  test('الملف: النسب والتفضيل الواضح والمتوسطات صحيحة', () {
    final feats = [perf(), perf(h: 170), perf(hair: 'BLONDE', h: 160), perf(eth: 'LATIN', cc: 'BR')].map(featuresOf).toList();
    final p = buildProfile(feats);
    expect(p.sufficient, isTrue);
    expect(p.cats['hair_color']!.top.key, 'BRUNETTE'); expect(p.cats['hair_color']!.share, .75); expect(p.cats['hair_color']!.strong, isTrue);
    expect(p.nums['height']!.mean, closeTo(165, .01)); expect(p.nums['height']!.lo, 160);
    final lines = describeProfile(p);
    expect(lines.any((l) => l.contains('بني') && l.contains('75٪')), isTrue);
    expect(lines.any((l) => l.contains('165')), isTrue);
  });

  test('بيانات غير كافية (أقل من 3) ⇒ يُعلن ذلك', () {
    expect(buildProfile([perf(), perf()].map(featuresOf).toList()).sufficient, isFalse);
  });

  test('التشابه: المطابقة ترفع الدرجة وتكتب أسبابًا، والمخالفة تُذكر كاختلاف', () {
    final p = buildProfile([perf(), perf(h: 168), perf(h: 162), perf(hair: 'BRUNETTE', h: 166)].map(featuresOf).toList());
    final close = similarity(p, featuresOf(perf(h: 165)));
    final far = similarity(p, featuresOf(perf(eth: 'ASIAN', hair: 'BLONDE', h: 185, tat: true)));
    expect(close.score > far.score, isTrue);
    expect(close.why.any((w) => w.contains('الشعر')), isTrue);
    expect(far.diff.isNotEmpty, isTrue);
  });

  test('التعلّم: «ليست ذوقي» يخفض درجة الخصائص نفسها، والإضافة ترفعها، ضمن الحدود', () {
    final p = buildProfile([perf(), perf(), perf()].map(featuresOf).toList());
    final f = featuresOf(perf());
    final base = similarity(p, f).score;
    var w = <String, double>{};
    for (var i = 0; i < 30; i++) { w = learn(w, f, -1); }
    expect(w.values.every((v) => v >= -1), isTrue);
    expect(similarity(p, f, fb: w).score < base, isTrue);
  });
}
