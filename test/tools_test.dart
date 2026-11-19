// منطق الأدوات: Elo، المستوى التلقائي، اكتمال السجل، واختيار زوج المواجهة.
import 'dart:math';

import 'package:favorites2/domain/elo.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Elo: الفائز يرتفع والخاسر ينخفض بنفس المقدار (K=32)', () {
    final (w, l) = eloUpdate(1000, 1000);
    expect(w, 1016); expect(l, 984);
    final (w2, _) = eloUpdate(1400, 1000); expect(w2 - 1400 < 16, isTrue); // فوز متوقع ⇒ زيادة أقل
  });
  test('المستوى من التقييم', () {
    expect([tierFromRating(5), tierFromRating(4.5), tierFromRating(3), tierFromRating(2), tierFromRating(1), tierFromRating(0)], ['S', 'A', 'B', 'C', 'D', '']);
  });
  test('اكتمال السجل: 7 فحوص', () {
    final full = Performer({'id': 'a', 'name': 'A', 'photos': ['https://x/1'], 'birth': '1990-01-01', 'country': 'US', 'stashId': 's', 'rating': 4, 'works': [{'t': 'W'}], 'tags': ['t']});
    expect(completeness(full).every((c) => c.$2), isTrue);
    expect(completeness(Performer({'id': 'b', 'name': 'B', 'birth': '1990'})).where((c) => c.$2).length, 0);
  });
  test('زوج المواجهة: ممثلتان مختلفتان، ولا زوج مع أقل من اثنتين', () {
    final pool = [for (var i = 0; i < 10; i++) Performer({'id': 'p$i', 'name': 'P$i', 'elo': 1000 + i * 10})];
    for (var k = 0; k < 50; k++) { final pr = pickPair(pool, Random(k))!; expect(pr.$1.id == pr.$2.id, isFalse); }
    expect(pickPair([pool.first], Random()), isNull);
  });
}
