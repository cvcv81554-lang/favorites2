// ذوق الأعمال: من تقييماتك ومشاهداتك فقط، ترتيب أعمال لم تشاهدها، أسباب حقيقية، والتقييم المنخفض يُبعد.
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> w(String t, String s, {int r = 0, bool seen = false, List<String> tg = const [], String d = '2023-01-01'}) =>
  {'t': t, 's': s, 'd': d, if (r > 0) 'r': r, if (seen) 'w': 1, 'tg': tg};

void main() {
  final a = Performer({'id': 'a', 'name': 'Alpha', 'fav': true, 'works': [
    w('Loved 1', 'Studio Good', r: 5, tg: ['Outdoor']), w('Loved 2', 'Studio Good', r: 5, tg: ['Outdoor']), w('Loved 3', 'Studio Good', r: 4, tg: ['Outdoor', 'Pov']),
    w('Meh 1', 'Studio Bad', r: 1), w('Meh 2', 'Studio Bad', r: 2),
    w('New Good', 'Studio Good', tg: ['Outdoor']), w('New Bad', 'Studio Bad'), w('New Neutral', 'Studio Other'),
  ]});
  final b = Performer({'id': 'b', 'name': 'Beta', 'works': [w('Seen B', 'Studio X', seen: true)]});

  test('الملف: الاستوديو والوسم المحبوبان في الصدارة بمتوسط تقييمك', () {
    final t = buildWorkTaste(groupWorks([a, b]));
    expect(t.sufficient, isTrue);
    expect(t.top('st:').first.label, 'Studio Good'); expect(t.top('st:').first.avgR, closeTo(14 / 3, .01));
    expect(t.top('tg:').first.label, 'Outdoor');
    expect(t.top('st:').any((k) => k.label == 'Studio Bad'), isFalse);   // التقييم المنخفض لا يظهر كتفضيل
  });

  test('الاقتراح: غير المُشاهد من الاستوديو المحبوب أولًا وبسببه، والمكروه لا يُقترح، ولا اقتراح بلا سبب', () {
    final groups = groupWorks([a, b]);
    final picks = recommendWorks(groups, buildWorkTaste(groups));
    expect(picks.first.g.t, 'New Good');
    expect(picks.first.why.first, contains('Studio Good'));
    expect(picks.any((p) => p.g.t == 'New Bad' && p.score > picks.first.score), isFalse);
    expect(picks.any((p) => p.g.seen || p.g.r > 0), isFalse);            // لا مُشاهد ولا مقيّم
    for (final p in picks) { expect(p.why, isNotEmpty); }
  });

  test('بيانات قليلة (أقل من 5 إشارات) ⇒ يُعلن ذلك', () {
    final p = Performer({'id': 'c', 'name': 'C', 'works': [w('One', 'S', r: 5), w('Two', 'S', seen: true)]});
    expect(buildWorkTaste(groupWorks([p])).sufficient, isFalse);
  });

  test('الإصدارات القادمة لا تُقترح', () {
    final p = Performer({'id': 'd', 'name': 'D', 'fav': true, 'works': [for (var i = 0; i < 5; i++) w('L$i', 'Fav St', r: 5), w('Soon', 'Fav St', d: '${DateTime.now().year + 1}-01-01')]});
    final g = groupWorks([p]);
    expect(recommendWorks(g, buildWorkTaste(g)).any((x) => x.g.t == 'Soon'), isFalse);
  });
}
