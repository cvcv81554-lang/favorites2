// التقييم التفصيلي (قاعدة القديم) وروابط الحسابات الآمنة.
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('التقييم العام = متوسط المعايير مقرّبًا لـ 0.5، والجسم التفصيلي يحدد معيار الجسم', () {
    final r = applyRatings({'beauty': 5, 'charisma': 4}, {'face': 3, 'legs': 4});
    expect(r.criteria['body'], 3.5);
    expect(r.rating, 4.0); // (5+4+3.5)/3 = 4.17 ⇒ 4.0
    expect(applyRatings({}, {}).rating, 0);
  });
  test('قراءة المعايير من السجل (القيم الصفرية تُتجاهل)', () {
    final p = Performer({'id': 'a', 'name': 'A', 'criteria': {'beauty': 4, 'heat': 0}, 'bodyD': {'face': 5}});
    expect(criteriaOf(p), {'beauty': 4.0}); expect(bodyOf(p), {'face': 5.0});
  });
  test('روابط الحسابات: https فقط، وأسماء مستخدم آمنة', () {
    expect(accUrl({'p': 'instagram', 'v': '@sample.name'}), 'https://instagram.com/sample.name');
    expect(accUrl({'p': 'x', 'v': 'https://x.com/abc'}), 'https://x.com/abc');
    expect(accUrl({'p': 'x', 'v': 'http://evil.test'}), isNull);
    expect(accUrl({'p': 'instagram', 'v': 'bad name/../x'}), isNull);
    expect(accUrl({'p': 'website', 'v': 'example.com/page'}), 'https://example.com/page');
    expect(accUrl({'p': 'other', 'v': 'not a link'}), isNull);
  });
}
