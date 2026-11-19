import '../domain/performer.dart';

/// بيانات تجريبية محايدة (أسماء «نموذج»، صور من نطاق اختبار وهمي img.test) — تُحمَّل فقط عند ?demo=1
/// في نسخة الويب للاختبار الآلي ولقطات الشاشة. لا بيانات حقيقية.
List<Performer> demoLibrary() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const cc = ['US', 'CZ', 'ES', 'BR', 'HU', 'FR'];
  return List.generate(18, (i) {
    final n = i + 1;
    return Performer({
      'id': 'demo-$n', 'name': 'نموذج $n', 'aliases': n % 3 == 0 ? 'Sample $n' : '',
      'birth': '${1988 + i % 12}-0${1 + i % 9}-1${i % 9}', 'country': cc[i % cc.length],
      'rating': (i % 6) * .5 + 2.5 > 5 ? 5.0 : (i % 6) * .5 + 2.5, 'fav': i % 3 == 0, 'tier': ['S', 'A', 'B', ''][i % 4],
      'tags': [if (i % 2 == 0) 'وسم أ', if (i % 3 == 0) 'وسم ب'],
      'photos': [for (var k = 0; k < 1 + i % 4; k++) 'https://img.test/p${(i + k) % 12}.png'],
      'works': [for (var k = 0; k < 2 + i % 5; k++) {'t': 'عمل تجريبي $n-$k', 's': 'Studio ${k % 4}', 'd': '${2019 + k}-0${1 + k % 9}-15', if (k % 2 == 0) 'w': 1, if (k == 4) 'q': 1, 'p': 'https://img.test/w${k % 6}.png'}, if (i % 4 == 0) {'t': 'إصدار قادم $n', 's': 'Studio X', 'd': '2027-03-01'}],
      'notes': i % 5 == 0 ? 'ملاحظات تجريبية للسجل $n' : '',
      'added': now - i * 3 * 86400000, 'updated': now - i * 3600000, 'views': i % 4 == 0 ? 3 : 0, if (i % 4 == 0) 'lastView': now - i * 60000,
    });
  });
}
