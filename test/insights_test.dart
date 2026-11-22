// المزايا الجديدة: المسيرة، السهرة، التقييم بالمعايير، لماذا أحبها، خريطة الذوق، الذوق عبر الزمن، ألبومات الحقب، الإخفاء.
import 'package:favorites2/data/studio_repo.dart';
import 'package:favorites2/domain/insights.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:favorites2/domain/taste.dart';
import 'package:favorites2/domain/work_taste.dart';
import 'package:favorites2/domain/works.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> w(String t, String s, String d, {int r = 0, bool seen = false, int du = 0, String p = ''}) =>
  {'t': t, 's': s, 'd': d, if (r > 0) 'r': r, if (seen) 'w': 1, if (seen) 'wd': d, if (du > 0) 'du': du, if (p.isNotEmpty) 'p': p};

void main() {
  test('المسيرة: سنوات مرتبة، الذروة، أكثر الاستوديوهات، واتجاه التقييم', () {
    final p = Performer({'id': 'a', 'name': 'A', 'cs': 2016, 'works': [
      w('1', 'Alpha', '2018-01-01', r: 2), w('2', 'Alpha', '2019-01-01'), w('3', 'Beta', '2019-05-01', seen: true), w('4', 'Alpha', '2019-09-01'), w('5', 'Beta', '2021-01-01', r: 5)]});
    final c = careerOf(p);
    expect(c.years.map((y) => y.year), [2018, 2019, 2021]);
    expect(c.peak, 2019); expect(c.first, 2018); expect(c.last, 2021); expect(c.start, 2016);
    expect(c.topStudios.first.$1, 'Alpha'); expect(c.topStudios.first.$2, 3);
    expect(c.years[1].seen, 1); expect(c.trend, 3);
  });

  group('سهرة', () {
    final fav = Performer({'id': 'f', 'name': 'Fav', 'fav': true, 'works': [
      for (var i = 0; i < 6; i++) w('Rated $i', 'Good St', '2022-0${i + 1}-01', r: 5), w('Short', 'Good St', '2023-01-01', du: 25), w('Long', 'Good St', '2023-02-01', du: 95)]});
    final other = Performer({'id': 'o', 'name': 'Other', 'works': [w('Other unseen', 'Good St', '2023-03-01', du: 20), w('Never seen her', 'X', '2023-04-01')]});
    final g = groupWorks([fav, other]);
    final t = buildWorkTaste(g);
    test('لم يُشاهد فقط، والمدة تُحترم، ولا تتكرر ممثلة', () {
      final p = eveningPicks(g, t, maxMinutes: 30);
      expect(p.every((x) => !x.g.seen && x.g.du > 0 && x.g.du <= 30), isTrue);
      expect(p.map((x) => x.g.t).toSet(), {'Short', 'Other unseen'});
    });
    test('«ممثلة جديدة عليّ»: أعمال ممثلات لم تشاهد لهن شيئًا', () {
      final s = Performer({'id': 'f', 'name': 'Fav', 'fav': true, 'works': [w('Seen one', 'S', '2022-01-01', seen: true), w('Fav unseen', 'S', '2023-01-01')]});
      final g2 = groupWorks([s, other]);
      final p = eveningPicks(g2, buildWorkTaste(g2), mood: EveningMood.newFace);
      expect(p.every((x) => x.g.who.every((q) => q.id == 'o')), isTrue);
    });
  });

  test('التقييم بالمعايير: متوسطه إشارة ذوق، والعمل المقيّم بالمعايير لا يُقترح', () {
    expect(criteriaAvg({'perf': 5, 'photo': 3}), 4);
    final p = Performer({'id': 'a', 'name': 'A', 'works': [{'t': 'C', 's': 'S', 'd': '2023-01-01', 'rc': {'perf': 5, 'photo': 5, 'story': 4}}]});
    final g = groupWorks([p]).single;
    expect(g.rc['perf'], 5); expect(workSignal(g) > 1, isTrue);
  });

  test('لماذا أحبها: السمات المشتركة بعددها، والأقرب إليها أولًا', () {
    Map<String, Object> f(String hair, String eth, double h) => {'hair_color': hair, 'ethnicity': eth, 'height': h};
    final her = f('BRUNETTE', 'CAUCASIAN', 165);
    final shared = sharedTraits(her, [f('BRUNETTE', 'CAUCASIAN', 166), f('BRUNETTE', 'LATIN', 180), f('BLONDE', 'CAUCASIAN', 150)]);
    expect(shared.first.$2, 2);
    expect(shared.any((s) => s.$1.contains('بني')), isTrue);
    final close = closestTo<String>(her, [('far', f('BLONDE', 'ASIAN', 185)), ('near', f('BRUNETTE', 'CAUCASIAN', 164))]);
    expect(close.first.$1, 'near');
  });

  test('خريطة الذوق: المتشابهتان أقرب لبعضهما من المختلفة', () {
    Map<String, Object> f(String hair, String eth, double h) => {'hair_color': hair, 'ethnicity': eth, 'height': h};
    final pts = tasteMap([f('BRUNETTE', 'CAUCASIAN', 165), f('BRUNETTE', 'CAUCASIAN', 166), f('BLONDE', 'ASIAN', 185)]);
    double d((double, double) a, (double, double) b) => (a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2);
    expect(d(pts[0], pts[1]) < d(pts[0], pts[2]), isTrue);
    for (final p in pts) { expect(p.$1.abs() <= 1.0001 && p.$2.abs() <= 1.0001, isTrue); }
  });

  test('الذوق عبر الزمن: إضافات كل سنة وسماتها الغالبة ومشاهداتها', () {
    int ms(int y) => DateTime(y, 6, 1).millisecondsSinceEpoch;
    final lib = [
      Performer({'id': 'a', 'name': 'A', 'fav': true, 'added': ms(2024)}), Performer({'id': 'b', 'name': 'B', 'fav': true, 'added': ms(2024)}),
      Performer({'id': 'c', 'name': 'C', 'fav': true, 'added': ms(2025), 'works': [w('W', 'Studio Z', '2025-02-02', seen: true)]}),
    ];
    final feats = {'a': featuresOf({'hair_color': 'BLONDE'}), 'b': featuresOf({'hair_color': 'BLONDE'}), 'c': featuresOf({'hair_color': 'BLACK'})};
    final y = tasteOverTime(lib, groupWorks(lib), feats);
    expect(y.map((e) => e.year), [2024, 2025]);
    expect(y.first.added, 2); expect(y.first.traits.single, contains('أشقر'));
    expect(y.last.watched, 1); expect(y.last.studios.single, 'Studio Z');
  });

  test('ألبومات الحقب: لقطات المشاهد بسنة عملها (الأحدث أولًا) والشخصية وحدها', () {
    final p = Performer({'id': 'a', 'name': 'A', 'works': [w('Old', 'S', '2019-01-01', p: 'https://img.test/old.jpg'), w('New', 'S', '2024-01-01', p: 'https://img.test/new.jpg')]});
    final e = eraAlbums(p, [('https://img.test/new.jpg', 'still'), ('https://img.test/face.jpg', 'portrait'), ('https://img.test/old.jpg', 'still'), ('https://img.test/x.jpg', 'still')]);
    expect(e.map((x) => x.$1), ['صور شخصية', '2024', '2019', 'لقطات أخرى']);
    expect(e[1].$2, [0]); expect(e[2].$2, [2]);
  });

  test('الإخفاء بالفرز السريع يُحفظ ويُستعاد، والسجلات القديمة بلا الحقل تعمل', () {
    final x = StudioImg(id: '1', pid: 'p', url: 'https://img.test/a.jpg', src: 'stash', kind: 'portrait', found: 1, hid: true);
    expect(StudioImg.fromJson(x.toJson()).hid, isTrue);
    expect(StudioImg.fromJson({'id': '2', 'pid': 'p', 'url': 'u', 'found': 1}).hid, isFalse);
    expect(StudioImg(id: '3', pid: 'p', url: 'u', src: 's', kind: 'still', found: 1).toJson().containsKey('hid'), isFalse);
  });
}
