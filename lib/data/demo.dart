import '../domain/performer.dart';

/// بيانات تجريبية محايدة (أسماء «نموذج»، صور من نطاق اختبار وهمي img.test) — تُحمَّل فقط عند ?demo=1
/// في نسخة الويب للاختبار الآلي ولقطات الشاشة. لا بيانات حقيقية.
List<Performer> demoLibrary() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const cc = ['US', 'CZ', 'ES', 'BR', 'HU', 'FR'];
  return List.generate(18, (i) {
    final n = i + 1;
    return Performer({
      'id': 'demo-$n', 'name': 'نموذج $n', if (i < 8) 'stashId': 'S-demo-$n', 'aliases': n % 3 == 0 ? 'Sample $n' : '',
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

/// مرشحات اقتراح تجريبية محايدة (للعرض فقط).
List<Map<String, dynamic>> demoRecPool() {
  final y = DateTime.now().year;
  return List.generate(24, (i) => {
    'id': 'rec-$i', 'name': 'مرشحة ${i + 1}', 'birth': i % 6 == 0 ? '${y - 19}-01-0${1 + i % 8}' : '${y - 24 - i % 12}-05-1${i % 9}',
    'country': ['US', 'CZ', 'ES', 'BR'][i % 4], 'image': 'https://img.test/p${(i + 3) % 12}.png', 'cs': y - (i % 7), 'sc': 10 + i * 7,
    'w': [if (i % 3 == 0) 'S-demo-1', if (i % 4 == 0) 'S-demo-4', if (i % 5 == 0) 'S-demo-7'], 'l': [if (i % 4 == 1) 'debut', if (i % 3 == 2) 'country'],
  });
}
