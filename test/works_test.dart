// دمج الأعمال عبر الممثلات وتطبيق التعديل على كل النسخ.
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = Performer({'id': 'a', 'name': 'A', 'works': [{'t': 'Shared Scene!', 's': 'Studio X', 'd': '2024-01-02', 'r': 3}, {'t': 'Solo A', 's': 'S', 'y': '2020'}]});
  final b = Performer({'id': 'b', 'name': 'B', 'works': [{'t': 'shared scene', 's': 'studio x', 'w': 1, 'wd': '2025-05-05', 'r': 5, 'p': 'https://img.test/x.jpg'}]});

  test('نفس العنوان والاستوديو (بصيغ مختلفة) = عمل واحد يجمع الممثلتين', () {
    final g = groupWorks([a, b]);
    expect(g.length, 2);
    final s = g.firstWhere((x) => x.who.length == 2);
    expect(s.seen, isTrue); expect(s.r, 5); expect(s.p, 'https://img.test/x.jpg'); expect(s.d, '2024-01-02'); expect(s.wd, '2025-05-05');
  });

  test('تعديل العمل يُطبَّق على نسخته عند كل ممثلة ويحدّث updated', () {
    final s = groupWorks([a, b]).firstWhere((x) => x.who.length == 2);
    final out = applyToGroup(s, (w) => w['q'] = 1);
    expect(out.length, 2);
    for (final p in out) { expect(p.works.where((w) => w['q'] == 1).length, 1); }
    expect(out.firstWhere((p) => p.id == 'a').works[1]['q'], isNull); // العمل الآخر لم يُمس
  });

  test('القادم: تاريخ مستقبلي غير مشاهد', () {
    final p = Performer({'id': 'c', 'name': 'C', 'works': [{'t': 'Future', 'd': '2999-01-01'}, {'t': 'Past', 'd': '2001-01-01'}, {'t': 'FutureSeen', 'd': '2999-01-01', 'w': 1}]});
    final g = groupWorks([p]);
    expect(g.firstWhere((x) => x.t == 'Future').isUpcoming, isTrue);
    expect(g.firstWhere((x) => x.t == 'Past').isUpcoming, isFalse);
    expect(g.firstWhere((x) => x.t == 'FutureSeen').isUpcoming, isFalse);
  });

  test('مشهدان مختلفان بنفس العنوان والاستوديو لا يندمجان (معرّف مختلف) ولا يتبادلان الصور', () {
    final x = Performer({'id': 'x', 'name': 'X', 'works': [{'t': 'Interview', 's': 'Studio', 'is': 'AAA', 'p': 'https://img.test/a.jpg'}, {'t': 'Interview', 's': 'Studio', 'is': 'BBB', 'p': 'https://img.test/b.jpg'}]});
    final g = groupWorks([x]);
    expect(g.length, 2);
    expect(g.firstWhere((e) => e.key == 'is:AAA').p, 'https://img.test/a.jpg');
    expect(g.firstWhere((e) => e.key == 'is:BBB').p, 'https://img.test/b.jpg');
  });

  test('نسخة بلا معرّف تُلحق بالمجموعة الوحيدة ذات المعرّف، ومفتاح المجموعة يُحدد بالموضع', () {
    final a = Performer({'id': 'a', 'name': 'A', 'works': [{'t': 'Same Scene', 's': 'St', 'is': 'S1', 'p': 'https://img.test/s1.jpg'}]});
    final b = Performer({'id': 'b', 'name': 'B', 'works': [{'t': 'same scene', 's': 'st', 'w': 1}]});
    final g = groupWorks([a, b]);
    expect(g.length, 1); expect(g.single.who.length, 2); expect(g.single.seen, isTrue);
    expect(groupKeyOf(g, 'b', 0), 'is:S1');
  });
}
